# PR #3 Review — Machines completion, UI/i18n polish, entities-backed directories

- **PR:** [#3](https://github.com/BeamLabEU/phoenix_kit_manufacturing/pull/3)
- **Author:** timujinne (Tymofii Shapovalov)
- **State:** MERGED (`bbbc0ec`)
- **Reviewer:** Claude (Sonnet 5)
- **Date:** 2026-07-14
- **Skills applied first:** `elixir:phoenix-thinking` + `elixir:ecto-thinking` (PR spans LiveView forms/lists, a new Ecto-backed attachments/comments layer, and an ETS+PubSub entities cache)

## Scope

A large PR (58 files, ~12,600 insertions): dynamic `metadata` fields driven by
per-machine-type `field_template`s, an Operations tab, a Files/attachments system
(`Attachments`, `FilesCard`), a Comments tab, per-user column
management/filtering (`ColumnConfig`, `ColumnManagement`, `ViewConfigs`,
`column_modal.ex`), and the `phoenix_kit_entities`-backed `machine_type`/
`operation`/`defect_reason` directories (`EntitiesRegistry`) replacing the old
module-owned CRUD tables.

Given the size, review was split across four parallel passes (LiveView forms,
list/column UI, machines context + entities registry, attachments/comments/module
registration), each tracing claims into the actual `phoenix_kit`/
`phoenix_kit_entities`/`phoenix_kit_comments`/`phoenix_kit_locations` core
dependencies rather than assuming their behavior. The two most severe findings
were independently re-verified by reading the code directly before fixing.

## Verdict

Ambitious, mostly well-executed PR with good defensive-programming discipline in
most of the new code (rescue-wrapping, soft cross-module references, batched
location-label resolution). Two real bugs made it through, though: a
GenServer-crash-on-boot in `EntitiesRegistry` for hosts where `phoenix_kit_entities`
isn't migrated yet, and a silent data-loss bug in the new dynamic `metadata` fields.
Both are fixed below, along with a real (if smaller-blast-radius) N+1 and a couple
of medium-severity gaps. Several additional findings are documented but
deliberately left unfixed — mostly because fixing them safely requires either a
running Postgres + browser to verify (unavailable in this review environment) or a
product decision this review shouldn't make unilaterally.

## Findings — Fixed

### BUG - CRITICAL — `EntitiesRegistry.init/1` can crash the host's supervision tree — FIXED
`lib/phoenix_kit_manufacturing/entities_registry.ex`

`do_reload/1` (called from `init/1`) built its ETS payload with:
```elixir
payload = Enum.flat_map(@entity_names, fn {kind, name} -> build_kind(kind, name) end)
```
`build_kind/2` calls `Entities.get_entity_by_name/1` — the exact same query
`provision_blueprints/0` (called one line earlier) is carefully wrapped in
`rescue`/`catch :exit` for, precisely because a host can boot before
`phoenix_kit_entities`' own tables are migrated (a separate migration namespace
from this module's core-V144 tables). But nothing protected this second,
identical-shaped call — a `Postgrex.Error` (`:undefined_table`) here propagated
straight out of `init/1`, which would exceed the supervisor's restart intensity
and could take down the whole `PhoenixKit.Supervisor` tree the host app runs
under. This directly contradicted the module's own documented convention
(`enabled?/0` rescues + catches `:exit`; LiveViews degrade instead of crashing).

**Fix:** extracted the payload-building step into `build_payload/0`, wrapped with
the same `rescue Postgrex.Error (:undefined_table)` / generic rescue / `catch
:exit` pattern as `provision_blueprints/0`. On failure, `do_reload/1` leaves the
ETS table untouched and returns the current `blueprints_provisioned` flag
unchanged — the next reload (PubSub-triggered, or the timer-driven
`:retry_provision`) retries.

Not covered by an automated test: reproducing "entities tables not migrated" in
this suite requires actually dropping/renaming live Postgres tables mid-run
under the Ecto Sandbox, which I judged too risky to improvise without being able
to run and verify it (no PostgreSQL is available in this review environment —
see "Validation" below). The fix mirrors `provision_blueprints/0`'s own
already-tested rescue shape exactly, so the risk is well understood, but a real
integration test simulating this boot state would be a good follow-up.

### BUG - HIGH — Typed-but-unsaved dynamic `metadata` values silently reset — FIXED
`lib/phoenix_kit_manufacturing/web/machine_form_live.ex`

`dynamic_metadata_field/1` rendered every dynamic spec input's value from
`assigns.machine.metadata` — the frozen struct assigned at `mount`/
`handle_params`, never updated by `handle_event("validate", ...)` (which only
touches `@changeset`/`@form`). Toggling a machine type (`toggle_type`)
recomputes `@merged_template` to reflect the new type selection, which
re-renders the "Specifications" comprehension. Verified directly (not just by
the sub-review) that depending on how the row list reshuffles, this replay can
resend a *different* row's rendered value at the DOM position where the user's
still-unsaved input sits, clobbering it with the frozen (blank or stale)
`@machine.metadata` value — a real, silent data-loss path in a core feature of
this PR.

**Fix:** `dynamic_metadata_field/1` now takes `:changeset` instead of `:machine`
and reads `Ecto.Changeset.get_field(changeset, :metadata)` — which reflects
every dynamic field submitted as of the last `validate` (all dynamic fields
share the same `<.form phx-change="validate">`), falling back to the machine's
saved metadata only for a key that's never yet been submitted (e.g. a
just-toggled-on type). `prepare_params/2` (used at actual save time) already
read fresh submitted `params` directly, so this fix is scoped purely to the
render path and doesn't change save semantics.

**Test:** added `"a typed-but-unsaved value survives toggling a second type on"`
to `test/phoenix_kit_manufacturing/web/machine_form_live_test.exs` — types into
a dynamic field via `render_change/1`, toggles a second type on, and asserts the
typed value is still present in the rendered HTML. This test would have failed
before the fix.

### BUG - HIGH — Unbatched N+1 thumbnail lookup, doubled by the table+card dual layout — FIXED
`lib/phoenix_kit_manufacturing/web/machines_live.ex`

`featured_thumbnail_file/1` called `Storage.get_file/1` (a single-row `repo().get`)
once per machine, per render. `table_default_with_cards/1` (core) renders **both**
the desktop table and the mobile card layout unconditionally in the same response
(visibility toggled with CSS, not conditional rendering), so this ran twice per
row with a featured image — on every debounced search keystroke, sort click, and
filter change, not just initial load. Notably, `location_labels/2` in the same
file already batches its own cross-module lookups with an explicit comment
explaining why — the same discipline wasn't applied to the new thumbnail feature.

**Fix:** added `featured_files_by_machine/1`, following the exact
`location_labels/2` pattern — collects distinct `featured_image_uuid`s across the
whole list, resolves them in one `Storage.get_files/1` query (already existed in
core, just unused here), and attaches the resolved file to each enriched machine
map as `:featured_file`. `featured_thumbnail_file/1` now just reads that
precomputed field.

Not covered by an automated test: constructing a real `Storage.File` fixture
requires a configured storage bucket + a source file on disk, which this test
suite doesn't currently set up anywhere (checked — `attachments_test.exs` only
exercises pure/stateless helpers). Verified correct by static reading: the
batched map is keyed by `machine.uuid` exactly as before, so per-machine
attribution can't cross-contaminate. A live-file integration test is a good
follow-up once Storage bucket fixtures exist in this suite.

### BUG - MEDIUM — Stale/renamed persisted columns silently degrade instead of falling back to defaults — FIXED
`lib/phoenix_kit_manufacturing/web/column_management.ex`

`assign_column_state/2` only fell back to `default_columns()` when the *raw*
persisted `columns` list was itself `[]` — not when `validate_columns/1`
reduces a non-empty-but-now-stale list (e.g. every persisted column id was
renamed/removed since the config was saved, or the columns modal's own "deselect
everything and Apply" flow) down to `[]`. The result wasn't a crash, but a table
rendering zero data columns (just "Actions") for every row.

**Fix:** now falls back to `default_columns()` whenever the *validated* result
is empty, regardless of whether the raw persisted list was empty or just
entirely stale.

### BUG - MEDIUM — Duplicate type uuid in `sync_machine_types/3` raised an uncaught `Ecto.ConstraintError` — FIXED
`lib/phoenix_kit_manufacturing/schemas/machine_type_assignment.ex`,
`lib/phoenix_kit_manufacturing/machines.ex`

Core V144 installs a unique index on `(machine_uuid, machine_type_uuid)`, but the
changeset had no matching `unique_constraint/2` — only `assoc_constraint(:machine)`.
A duplicate uuid in the caller's list (the public context API's type is
`[String.t()]`, nothing prevented this) would raise a raw `Ecto.ConstraintError`
from inside the transaction instead of the documented `{:error,
:type_assignment_failed}`. Not reachable through the shipped UI today (the form
always feeds a deduped `MapSet.to_list/1`), so this was latent rather than
actively triggered — but a real gap in the public API's contract.

**Fix:** added `unique_constraint([:machine_uuid, :machine_type_uuid], name:
:idx_machine_type_assignments_unique)` to `MachineTypeAssignment.changeset/2`.
`insert_type_assignment!/3` already handled `{:error, %Ecto.Changeset{}}`
correctly, so no other code changed.

**Test:** added `"a duplicate type uuid in the list returns a clean error instead
of raising"` to `test/phoenix_kit_manufacturing/machines_test.exs`.

### IMPROVEMENT - MEDIUM — `Comments.available?/0` didn't follow this module's own DB-unavailable convention — FIXED
`lib/phoenix_kit_manufacturing/comments.ex`

Every other "is this optional dependency alive" check in this module (e.g.
`PhoenixKitManufacturing.enabled?/0`) both `rescue`s and `catch`es `:exit`, to
handle the documented sandbox-owner-exited race. `Comments.available?/0` only
had the bare `Code.ensure_loaded?/1 and enabled?()` call, with neither — despite
the moduledoc explicitly claiming "every function degrades gracefully... callers
never special-case it."

**Fix:** added the matching `rescue`/`catch :exit` clauses.

## Findings — Documented, not fixed

### BUG - HIGH — `attachments.ex` upload content-type/extension isn't validated against actual file content
`lib/phoenix_kit_manufacturing/attachments.ex`, traced into
`phoenix_kit`'s `Storage.store_file_in_buckets/6` / `determine_mime_type/1`.

Neither this module nor core's `Storage` sniffs magic bytes — the MIME type is
looked up from the client-supplied extension via a small static allow-map, and
`file_type_from_mime/1` is a category check, not a content check. Blast radius is
currently bounded by that allow-map only recognizing image/video/audio/pdf
extensions (everything else falls back to `application/octet-stream`), but this
module adds no allow-list of its own before handing `entry.client_name`/
`entry.client_type` to `Storage`. **Not fixed:** the right allow-list depends on
which file types this module actually intends to support, which is a product
decision I shouldn't make unilaterally by guessing; recommend a short follow-up
with the author to pick and enforce an explicit extension allow-list in
`Attachments.store_upload/4`.

### BUG - MEDIUM — `Content-Disposition` header uses the raw client filename, unescaped
Root cause is core's `phoenix_kit`
`lib/phoenix_kit_web/controllers/file_controller.ex:555-558`
(`~s(inline; filename="#{file.original_file_name}")`), fed by
`entry.client_name` via this PR's new `attachments.ex:705` call site. A filename
containing `"` breaks out of the quoted parameter. **Not fixed here:** the fix
belongs in core (`phoenix_kit`), not this repo; this module could add
defense-in-depth by stripping `"`/control characters from the filename before
storing, which would be a reasonable small follow-up.

### BUG - MEDIUM — `Attachments.forget_scope/2` is dead code; abandoned "new machine" drafts leak pending Storage folders
`lib/phoenix_kit_manufacturing/attachments.ex`

Documented as "call when a draft is discarded so the per-scope map doesn't grow
unbounded," but it's never called anywhere (confirmed via repo-wide grep).
Uploading files on a `:new` machine and navigating away without saving leaves a
real, populated `"machine-attachment-pending-<uuid>"` Storage folder with no
reaper — core's orphan-file cleanup only targets files with `folder_uuid == nil`,
which doesn't apply here since these files are validly homed in a real (if
abandoned) folder. **Not fixed:** the correct hook point is unclear without being
able to exercise the actual Cancel/navigate-away flow in a running browser (no
dev server / DB available in this review environment — `terminate/2` isn't
reliable here either, per the `phoenix-thinking` skill's own gotcha about
`trap_exit`), so I didn't want to land an unverified guess at the fix. Flagging
as a real, if slow-burning, resource leak worth a dedicated follow-up.

### BUG - MEDIUM — Interactive `machines_live.ex` event handlers bypass this module's rescue convention
`lib/phoenix_kit_manufacturing/web/machines_live.ex`

Only the initial `load_data`/PubSub-triggered reload paths wrap `assign_machines/1`
in `rescue`; `search`/`set_sort`/`toggle_sort`/`flip_sort_dir`/`clear_all_filters`
and the column-management macro's filter/save handlers all call it directly. A
transient DB error mid-interaction would crash the LiveView instead of degrading
with a flash, inconsistent with the rest of this file. **Not fixed:** touching
every handler is a broader, mechanical change I'd want to batch with the
DB-unavailable improvement below rather than do piecemeal; tracked as a follow-up.

### IMPROVEMENT - HIGH — `machine_form_live.ex` recomputes comment count + location label on every keystroke
`lib/phoenix_kit_manufacturing/web/machine_form_live.ex`

The tab bar's `Comments.count/2` and the Location card's `location_summary/4` (→
`Spaces.full_path/2`, a preload + a `get` + a recursive-CTE query) are computed
inline in `render/1` rather than memoized into an assign — so they re-run on
every `phx-change="validate"` event, i.e. every keystroke while editing a machine
that has comments and/or a location. **Not fixed:** memoizing these correctly
requires also invalidating the cache after posting a comment (or the count would
go stale immediately after use), which is more surgery than I wanted to do
without a running app to click through and confirm the count still updates live
after posting — flagged as a follow-up rather than risking a regression in count
freshness.

### IMPROVEMENT - MEDIUM — Minor items, no action needed
- `entities_registry.ex`: a narrow (sub-millisecond, self-healing) stale-read
  window between the atomic ETS payload insert and the separate stale-key
  cleanup loop within the same `do_reload/1` call. The moduledoc's "always
  consistent" claim is very slightly imprecise but not a functional bug.
- `machines.ex`: `sync_machine_types/3`/`sync_machine_operations/3` do N
  individual `Repo.insert/1` calls instead of `Repo.insert_all/3` — safe
  (transactional) but not batched; fine at "a handful of type badges per
  machine" scale, worth revisiting if that grows.
- `view_configs.ex`: `merge_view_config/3` is read-then-write, not atomic —
  two concurrent saves for the same user could clobber each other's changes.
  Low impact (single-user browser preference, not shared data).
- `comments.ex`: moduledoc calls `PhoenixKitComments` "optional," but
  `mix.exs` declares it a hard `pk_dep` + `extra_applications` entry with no
  `optional: true` — so the "absent" branch of every `Code.ensure_loaded?/1`
  check is effectively unreachable in any real install. Misleading framing,
  not a functional bug.

### NITPICK - Minor items, no action needed
- `machine_type_template_live.ex:290` — stale comment referencing the deleted
  `Schemas.MachineType.validate_field_template/1`.
- `schemas/machine.ex` — `maybe_compute_next_maintenance/1`'s doc says an
  explicit override "always wins," which is imprecise for an explicit `nil`
  (indistinguishable from "not submitted").
- `machine_form_live.ex` — `sync_and_redirect/3` runs `sync_machine_types` and
  `sync_machine_operations` as two independent transactions; a failure between
  them leaves a partial save with only a generic warning flash. Narrow edge
  case (requires an actual mid-flow DB failure).
- `machine_type_template_live.ex` — one DB read directly in `mount/3`; not
  a real issue since this view has no `handle_params/3` to defer it to, and the
  reads are cheap single-row PK lookups.
- `column_modal.ex` — duck-types `column_config` (a bare atom) via
  `column_metadata_map/0`/`available_columns/0`, with no compile-time guarantee
  the passed module implements that shape. Documented dependency, not a bug.

## Validation

- `mix compile --warnings-as-errors` — clean, no warnings.
- `mix format --check-formatted` — clean (one new test file needed
  `mix format`, now applied).
- `mix test` — 118 unit tests pass, 0 failures (104 integration tests
  auto-excluded: no PostgreSQL is available in this review environment).
  **The new/modified tests in this PR have not been run against a live
  database** — please run `mix test` (or `PHOENIX_KIT_PATH=... PHOENIX_KIT_LOCATIONS_PATH=... mix test`
  per this repo's local cross-repo dev setup) with Postgres available before
  relying on this as a release gate.
- `mix credo --strict` — exits non-zero both before and after this review's
  changes (confirmed by diffing against the pre-review commit): 3 pre-existing
  refactoring opportunities + 3 design suggestions in files this PR didn't
  touch (`column_config.ex`, `column_config/machines.ex`,
  `web/machines_live.ex` mount/load_data nested-alias suggestions,
  `web/column_management.ex`). Not a regression introduced by this review or
  by PR #3; pre-existing debt worth a separate cleanup pass.
- `mix dialyzer` — passed successfully (2 pre-existing entries suppressed via
  `.dialyzer_ignore.exs`, unrelated to this review's changes).
