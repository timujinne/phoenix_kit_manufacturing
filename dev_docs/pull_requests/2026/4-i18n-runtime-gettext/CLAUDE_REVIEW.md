# PR #4 Review — Make 11 runtime-gettext UI strings translatable (et/ru)

- **PR:** [#4](https://github.com/BeamLabEU/phoenix_kit_manufacturing/pull/4)
- **Author:** timujinne (Tymofii Shapovalov)
- **State:** MERGED (`820177f`)
- **Reviewer:** Claude (Sonnet 5)
- **Date:** 2026-07-17
- **Skill applied first:** `elixir:phoenix-thinking` (touches a LiveView `use`-macro and flash-message call sites)

## Scope

Small, focused fix (2 source files, 3 catalog files): 11 UI strings in
`PhoenixKitManufacturing.Attachments` and `PhoenixKitManufacturing.Web.ColumnManagement`
were calling `Gettext.gettext(PhoenixKitWeb.Gettext, "...")` /
`Gettext.dgettext(PhoenixKitManufacturing.Gettext, "default", "...")` directly —
fully-qualified runtime calls that `mix gettext.extract` cannot see, since
extraction only recognizes the `gettext`/`dgettext` **macros** brought in by
`use Gettext, backend: ...`. Both modules now do `use Gettext, backend:
PhoenixKitManufacturing.Gettext` and call the macros directly, and the 11
strings (upload/attachment error flashes, column-management save flashes) were
added to `priv/gettext/{default.pot,en,et,ru}` with et/ru translations filled in.

Notably this also **fixes a backend-ownership bug in `attachments.ex`**: those 5
error-flash strings were previously tied to `PhoenixKitWeb.Gettext` — the
*host* app's Gettext backend — even though they're strings this module owns and
ships its own et/ru catalogs for. A host without those exact msgids in its own
catalog would have rendered them untranslated regardless of locale. Routing
them through the module's own `PhoenixKitManufacturing.Gettext` (matching
`column_management.ex` and every other module file, confirmed via
repo-wide grep — no `PhoenixKitWeb.Gettext` references remain) is the correct
fix, not just a style change.

## Verification

- Confirmed the two `dgettext` call sites in `column_management.ex` (lines
  242, 252) are inside `save_view_config/6`, a plain function defined directly
  on the module — **not** inside the `defmacro __using__` quoted block that
  gets injected into host LiveViews. So `use Gettext, backend: ...` at the
  top of the module is in scope for those calls; had they been inside the
  quoted block, the injected code would have needed its own `use Gettext` in
  each consuming LiveView instead. No such issue in `attachments.ex` either
  (plain context module, no macro injection).
- Diffed `priv/gettext/default.pot`: exactly the 11 expected new msgids
  appear (`Columns updated`, `Could not prepare the files folder.`, `Could
  not remove file.`, `Failed to save columns`, `File is too large.`, `File
  type not accepted.`, `Selected image could not be loaded.`, `Too many
  files.`, `Upload error: %{reason}`, `Upload failed for %{name}.`, `Upload
  failed: no target file area selected.`) — no msgid mismatches against the
  source strings. et/ru `msgstr`s are filled in and read as sensible
  translations (spot-checked all 11 in both locales), not placeholder/blank.
  The remaining `.pot`/`.po` diff noise is pre-existing entries shifting
  `#:` line-number references from unrelated line churn elsewhere in the repo.
- Repo-wide grep for `PhoenixKitWeb.Gettext` and fully-qualified
  `Gettext.gettext(`/`Gettext.dgettext(` calls: zero remaining hits — the
  migration is complete and consistent, not a partial fix that left other
  call sites on the old pattern.

## Verdict

Correct, minimal fix with no regressions. No findings.

## Gate

Ran the project's gate against the merged state (`820177f`, i.e. post-merge on
`main`):

- `mix compile --warnings-as-errors` — clean
- `mix format --check-formatted` — clean
- `mix credo --strict` — 3 pre-existing Design/Refactoring notes, none in
  files or lines this PR touched (`column_config.ex`, `column_config/machines.ex`,
  and one nested-module note in `machines_live.ex`); confirmed unrelated to
  this PR's diff.
- `mix dialyzer` — clean
- `mix test` (unit; DB unavailable so `:integration` auto-excluded per repo
  convention) — 118 tests, 0 failures

`mix precommit`'s `deps.unlock --check-unused` step originally failed
(`:ex_aws_sqs`, `:httpoison`, `:jose`, `:metrics`, `:ueberauth_apple`,
`:unicode_util_compat` unused in `mix.lock`) — confirmed via a throwaway
worktree at the pre-PR commit (`7c76b00`) that this predates PR #4 and the
subsequent `364a28e` "lib upgrades" commit entirely. Unrelated dependency
drift, out of PR #4's scope, but `mix hex.audit` also failed as part of this
release's pre-flight: `ueberauth_apple 0.6.1` carries a CRITICAL advisory
(CVE-2026-55954). Traced its origin — `phoenix_kit` 1.7.187 declared it as a
dependency; `phoenix_kit` dropped it by 1.7.191 (`2cc8f14`, "Finalize
dependency pins"), but the orphaned lock entry was never pruned since
`mix deps.get` alone doesn't remove stale entries. Not a declared dependency
of this package and never shipped to Hex consumers (`mix.lock` isn't
published), but cleaned up anyway via `mix deps.unlock --unused` as part of
the 0.3.1 release — see `CHANGELOG.md`.
