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
      # whole suite before any test starts. `up/1` is cumulative — one call
      # applies every version's statements — so `public` is always fully
      # migrated (currently V1 + V2 + V3) by the time this runs.
      assert Machines.migrated_version_runtime(prefix: "public") == Machines.current_version()
      assert Machines.migrated_version_runtime(prefix: "public") == 3
    end
  end

  describe "up/1 (V2 additions)" do
    test "every V2 structural addition exists on both tables it touched" do
      # `probe_v2?/1` must check *every* column V2 introduced, not one
      # representative (see moduledoc) — pin the exact set here so a future
      # edit that narrows the probe back down to a single column fails
      # loudly instead of silently masking a partial migration.
      new_machine_columns = ~w(
        model manufacture_year commissioned_on warranty_until to_last_on
        to_interval_days to_next_on notes location_uuid space_uuid
      )

      for column <- new_machine_columns do
        assert column_exists?("phoenix_kit_machines", column),
               "expected phoenix_kit_machines.#{column} to exist after up/1"
      end

      assert column_exists?("phoenix_kit_machine_types", "field_template")
    end
  end

  describe "up/1 (V3 additions)" do
    test "both V3 tables exist" do
      # `probe_v3?/1` must check *both* tables V3 introduced, not one
      # representative (see moduledoc) — pin that here so a future edit
      # that narrows the probe back to a single table fails loudly instead
      # of silently masking a partial migration.
      assert table_exists?("phoenix_kit_operations")
      assert table_exists?("phoenix_kit_machine_operations")
    end

    test "phoenix_kit_operations has the expected columns" do
      for column <- ~w(uuid name unit base_time_norm_seconds status data inserted_at updated_at) do
        assert column_exists?("phoenix_kit_operations", column),
               "expected phoenix_kit_operations.#{column} to exist after up/1"
      end
    end

    test "phoenix_kit_machine_operations has the expected columns" do
      columns = ~w(uuid machine_uuid operation_uuid time_norm_seconds inserted_at updated_at)

      for column <- columns do
        assert column_exists?("phoenix_kit_machine_operations", column),
               "expected phoenix_kit_machine_operations.#{column} to exist after up/1"
      end
    end

    test "idx_machine_operations_unique is a unique index on (machine_uuid, operation_uuid)" do
      query = """
      SELECT indexdef FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = $1 AND indexname = $2
      """

      assert {:ok, %{rows: [[indexdef]]}} =
               Repo.query(query, [
                 "phoenix_kit_machine_operations",
                 "idx_machine_operations_unique"
               ])

      assert indexdef =~ "UNIQUE"
      assert indexdef =~ "machine_uuid"
      assert indexdef =~ "operation_uuid"
    end
  end

  defp column_exists?(table, column) do
    query = """
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2
    """

    case Repo.query(query, [table, column]) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  end

  defp table_exists?(table) do
    case Repo.query("SELECT to_regclass($1)", ["public.#{table}"]) do
      {:ok, %{rows: [[nil]]}} -> false
      {:ok, %{rows: [[_oid]]}} -> true
      _ -> false
    end
  end
end
