# Legacy directory-table data migration (machine_types / operations / defect_reasons)

This is a one-time, manual runbook for hosts that installed
`phoenix_kit_manufacturing` **before** the core-migration consolidation
(published `0.2.0`, schema V1 — machine types, operations, and defect
reasons as plain module-owned tables) **and** have real rows in one or more
of:

- `phoenix_kit_machine_types`
- `phoenix_kit_operations`
- `phoenix_kit_defect_reasons`

Fresh installs, and any host where those three tables are empty or don't
exist, need nothing from this document — core migration
`PhoenixKit.Migrations.Postgres.V144` creates the module's current schema
directly and quietly drops the three tables itself when they exist and are
empty.

## Do you need this?

After upgrading `phoenix_kit` (core) to a version containing V144, run:

```sql
SELECT
  to_regclass('public.phoenix_kit_machine_types')  IS NOT NULL AS machine_types_left,
  to_regclass('public.phoenix_kit_operations')      IS NOT NULL AS operations_left,
  to_regclass('public.phoenix_kit_defect_reasons')  IS NOT NULL AS defect_reasons_left;
```

(Swap `public.` for your actual schema if PhoenixKit doesn't run in
`public`.) If any column comes back `true`, V144 found that table non-empty
and deliberately left it in place instead of risking a silent data drop —
check its row count and follow the steps below:

```sql
SELECT count(*) FROM phoenix_kit_machine_types;   -- only if machine_types_left = true
SELECT count(*) FROM phoenix_kit_operations;      -- only if operations_left = true
SELECT count(*) FROM phoenix_kit_defect_reasons;  -- only if defect_reasons_left = true
```

Until you do, the module's UI will show **"Unknown"** for any machine's
type/operation badges (`PhoenixKitManufacturing.EntitiesRegistry` has
nothing cached for the legacy-table uuids still sitting in
`phoenix_kit_machine_type_assignments.machine_type_uuid` /
`phoenix_kit_machine_operations.operation_uuid`) — the join columns
themselves are untouched by V144 (only the foreign-key *constraints* on
them are dropped), so no data is lost, it's just not visible yet through
the new `phoenix_kit_entities`-backed reads.

## Background

Through the module's own published `0.2.0` (schema V1), machine types,
operations, and defect reasons were plain module-owned tables, migrated by
`PhoenixKitManufacturing.Migrations.Machines` (the module's own
`migration_module/0`, run by `mix phoenix_kit.update`). This consolidation
wave moves the module's tables into core's migration chain
(`phoenix_kit` V144) and, at the module-code level, retires that V1
directory-table design in favor of `phoenix_kit_entities`-backed blueprint
records (`machine_type`, `operation`, `defect_reason`), read through
`PhoenixKitManufacturing.EntitiesRegistry`.

The **data**-conversion step that used to come with this — copying rows out
of the three legacy tables into `phoenix_kit_entities`/
`phoenix_kit_entity_data`, rewriting the
`phoenix_kit_machine_type_assignments.machine_type_uuid` /
`phoenix_kit_machine_operations.operation_uuid` join columns to point at
the new records, and dropping both legacy tables once empty — used to run
automatically as part of the module's own schema V5 migration. V144 does
**not** reproduce that step: a core schema migration has no business
depending on the optional `phoenix_kit_entities` package, and a schema
migration is the wrong place to run an unbounded, business-data conversion
against someone else's rows without their say-so. V144's own `up/1`
already drops the foreign-key *constraints* on both join columns
unconditionally (so those columns are free-standing soft references, same
as everywhere else in the module) — it just doesn't rewrite the values or
touch the three source tables when they still hold data. What's left is
exactly what this document walks through.

## Reference implementation

The exact, previously-shipped conversion code — the blueprint entity
definitions (`machine_type` / `operation` / `defect_reason` field templates
and `ru`/`et` translations), the multilang `data` reshaping (`_name` →
`_title`), the retry-safe `metadata["legacy_uuid"]` idempotency mapping,
and the join-table rewrite — is preserved in this repository's git history
at commit `f7d13e843839c90f70e67e71cf7d4b776928bec3` (the last commit
before this consolidation removed the file), as
`lib/phoenix_kit_manufacturing/migrations/machines.ex`. The relevant entry
point is `migrate_legacy_directories_to_entities/2` (private, called from
the end of `up/1`) and the private helpers below it in the same file
(`ensure_blueprint_entity/2`, `migrate_machine_types/4`,
`migrate_operations/4`, `migrate_defect_reasons/4`,
`convert_multilang_data/3`, `rewire_references/4`, and friends):

```bash
git show f7d13e843839c90f70e67e71cf7d4b776928bec3:lib/phoenix_kit_manufacturing/migrations/machines.ex
```

The logic was introduced in commit `47bc696` ("Add migration V5: migrate
machine_type/operation/defect_reason to phoenix_kit_entities") and last
touched in `d202df9` ("Fix rewire_references to run on the migration
transaction connection") — both reachable from the same history.

## Migration steps

Prerequisites: `phoenix_kit_entities` migrated on the target database, and
at least one PhoenixKit user account already created (used as
`created_by_uuid` on the blueprint entities and every migrated row).

This re-runs the exact original code as a one-off migration — the same
`Ecto.Migrator.up/4` invocation `mix phoenix_kit.update` used to generate
automatically for this module before this consolidation (mirrored 1:1 by
this repo's own `test/support/machines_migration.ex`), just triggered by
hand instead of by module auto-discovery.

1. Fetch the pre-consolidation source (only needed to copy from — not as a
   live dependency):
   ```bash
   git clone https://github.com/BeamLabEU/phoenix_kit_manufacturing /tmp/pkm-legacy
   cd /tmp/pkm-legacy && git checkout f7d13e843839c90f70e67e71cf7d4b776928bec3
   ```
2. Copy `lib/phoenix_kit_manufacturing/migrations/machines.ex` verbatim into
   your host app, e.g. as `lib/legacy_manufacturing_migration.ex` (the
   module name/location don't matter — nothing else in your app references
   it; keep it out of `priv/repo/migrations` so it's never picked up as a
   real numbered migration).
3. Add a thin `Ecto.Migration` wrapper next to it — `Machines.up/1` takes
   an options argument, so it can't be run directly as a migration's
   `up/0`:
   ```elixir
   defmodule LegacyManufacturingMigrationRunner do
     use Ecto.Migration
     alias PhoenixKitManufacturing.Migrations.Machines

     def up, do: Machines.up(prefix: "public")
     def down, do: raise("not supported — see the copied module's own moduledoc")
   end
   ```
   (Swap `prefix: "public"` if PhoenixKit doesn't run in `public` on your
   host.)
4. Run it once, against your production database, from `iex -S mix` (or a
   `mix run -e` one-liner):
   ```elixir
   Ecto.Migrator.up(MyApp.Repo, System.system_time(:microsecond), LegacyManufacturingMigrationRunner, log: false)
   ```
   This re-runs the *entire* V1→V5 `up/1` (it's cumulative by design — see
   the copied module's own moduledoc), which is safe even though your
   tables are already past V1: every DDL statement is `IF NOT EXISTS` /
   idempotent, so V1-V4 are no-ops against a database V144 already brought
   to the current shape. Only the last step,
   `migrate_legacy_directories_to_entities/2`, does real work: it
   idempotently ensures the three blueprint entities exist (reusing them if
   `EntitiesRegistry.init/1` already provisioned them on boot), converts
   and inserts each legacy row not already migrated (tracked via
   `metadata["legacy_uuid"]`, so a re-run after an interruption picks up
   where it left off instead of duplicating), rewrites both join-table
   columns to the new `phoenix_kit_entity_data` uuids, and finally drops
   all three legacy tables. Nothing further to clean up afterward.
5. As with any manual DDL/data run against a PgBouncer-fronted database,
   verify afterward instead of trusting a clean exit code alone (the
   underlying migration has always had this caveat — see its
   `@disable_ddl_transaction` note): re-run the "Do you need this?" query
   above (should now report `false`/nothing left), then
   `PhoenixKitManufacturing.EntitiesRegistry.reload()` followed by
   `PhoenixKitManufacturing.EntitiesRegistry.list(:machine_type, nil)` /
   `:operation` / `:defect_reason` — your migrated rows should be there,
   and a machine with a previously-linked type/operation should show its
   real name instead of "Unknown" on
   `/admin/manufacturing/machines/:uuid/edit`.
6. Delete the two scratch files from steps 2-3 — they were only needed for
   this one-off run.

### If you'd rather not run old migration code directly

The algorithm (see the reference commit above for exact code) is:

1. Idempotently ensure three `phoenix_kit_entities` blueprint entities exist
   (`machine_type`, `operation`, `defect_reason`) via
   `PhoenixKitEntities.get_entity_by_name/1` → `create_entity/2` +
   `set_entity_translation/3` for `ru`/`et` — see `@blueprint_directories`
   in the reference commit for the exact `display_name`/`icon`/
   `fields_definition`/translation values.
2. For every row in each of the three legacy tables, insert a
   `PhoenixKitEntities.EntityData` record via `EntityData.create/2`: title
   and (for `machine_type`/`defect_reason`) description go into the
   primary-language block of `data` as `_title`/`_description` (converting
   any existing multilang `_name` key to `_title` if the row already has
   translated data); `operation`'s `unit`/`base_time_norm_seconds` go into
   that same primary-language block, unprefixed; `machine_type`'s
   `field_template` goes to `metadata["field_template"]`, not `data`. Stamp
   `metadata["legacy_uuid"]` with the source row's uuid on every record
   (idempotency: skip a row whose `legacy_uuid` you've already migrated).
3. `UPDATE phoenix_kit_machine_type_assignments SET machine_type_uuid =
   <new uuid> WHERE machine_type_uuid = <old uuid>` for every mapped pair
   (and the equivalent for `phoenix_kit_machine_operations.operation_uuid`)
   — the foreign-key constraints these columns used to carry are already
   gone by this point (dropped unconditionally by V144's `up/1`), so
   there's nothing to drop yourself first.
4. `DROP TABLE phoenix_kit_machine_types / phoenix_kit_operations /
   phoenix_kit_defect_reasons` once you've verified every row migrated.

## Notes

- One-time, per-host, manual — not something the module or core will ever
  run automatically, for the reasons in "Background" above.
- Nothing to do if the three tables are empty or already gone — V144
  handled that case itself.
- Only the `machine_type_uuid` / `operation_uuid` columns on the two join
  tables change meaning (legacy-table uuid → `phoenix_kit_entity_data`
  uuid); `machine_uuid` on both, and every column of
  `phoenix_kit_machines` itself, are untouched by any of this.
