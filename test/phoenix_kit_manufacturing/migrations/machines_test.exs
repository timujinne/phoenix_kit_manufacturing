defmodule PhoenixKitManufacturing.Migrations.MachinesTest do
  # Integration tests for the version-probe protocol — require PostgreSQL,
  # excluded when the DB is unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.DataCase, async: true

  alias PhoenixKitManufacturing.Migrations.Machines

  describe "migrated_version_runtime/1" do
    test "returns 0 when the machines table does not exist under the given prefix" do
      # Probes against a schema that was never migrated, rather than
      # dropping the shared `public.phoenix_kit_machines` table that every
      # other integration test in the suite depends on. `to_regclass`
      # returns NULL (not an error) for a missing schema/table, so this
      # exercises the same "nothing migrated yet" code path.
      assert Machines.migrated_version_runtime(prefix: "no_such_schema_for_probe_test") == 0
    end

    test "returns current_version() once the module's tables are migrated" do
      # test_helper.exs runs `Machines.up(prefix: "public")` once for the
      # whole suite before any test starts, so `public` is always migrated
      # by the time this runs.
      assert Machines.migrated_version_runtime(prefix: "public") == Machines.current_version()
      assert Machines.migrated_version_runtime(prefix: "public") == 1
    end
  end
end
