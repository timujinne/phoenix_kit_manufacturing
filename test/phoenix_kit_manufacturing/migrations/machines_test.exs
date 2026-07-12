defmodule PhoenixKitManufacturing.Migrations.MachinesTest do
  # Integration tests for the version-probe protocol and the V5
  # machine_type/operation/defect_reason -> phoenix_kit_entities data
  # migration — require PostgreSQL, excluded when the DB is unavailable
  # (see test_helper.exs).
  use PhoenixKitManufacturing.DataCase, async: true

  alias PhoenixKit.Utils.Multilang
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
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
      # migrated (currently V1 through V5) by the time this runs.
      assert Machines.migrated_version_runtime(prefix: "public") == Machines.current_version()
      assert Machines.migrated_version_runtime(prefix: "public") == 5
    end
  end

  describe "up/1 (V2 additions)" do
    test "every V2 addition that survives V5 still exists on phoenix_kit_machines" do
      # `probe_v2?/1` must check *every* column V2 introduced, not one
      # representative (see moduledoc) — pin the exact set here so a future
      # edit that narrows the probe back down to a single column fails
      # loudly instead of silently masking a partial migration.
      #
      # V2 also added `phoenix_kit_machine_types.field_template` — that
      # table is dropped by V5 (see the "V5 — fresh host" describe block
      # below), so it is intentionally not checked here anymore.
      new_machine_columns = ~w(
        model manufacture_year commissioned_on warranty_until to_last_on
        to_interval_days to_next_on notes location_uuid space_uuid
      )

      for column <- new_machine_columns do
        assert column_exists?("phoenix_kit_machines", column),
               "expected phoenix_kit_machines.#{column} to exist after up/1"
      end
    end
  end

  describe "up/1 (V3 additions)" do
    test "the machine<->operation join table survives V5" do
      # `phoenix_kit_operations` (V3's other table) is dropped by V5 — see
      # the "V5 — fresh host" describe block below. Only the join table,
      # which V5 keeps (soft-referencing entity_data instead of a real FK),
      # is checked here.
      assert table_exists?("phoenix_kit_machine_operations")
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

  describe "up/1 (V5 — fresh host)" do
    # test_helper.exs runs `Machines.up(prefix: "public")` exactly once for
    # the whole suite, against a `public` schema that started completely
    # empty — a fresh `mix test.setup` createdb has no legacy directory
    # rows to migrate. That *is* the "fresh host directly reaches V5"
    # scenario: asserting against `public` here (rather than calling
    # `up/1` again) confirms one cumulative call reaches V5 with nothing
    # to migrate, which is exactly what already happened before any test
    # in this suite ran.
    test "reaches V5, drops the three legacy tables, and provisions the three blueprint entities" do
      assert Machines.migrated_version_runtime(prefix: "public") == 5

      refute table_exists?("phoenix_kit_machine_types")
      refute table_exists?("phoenix_kit_operations")
      refute table_exists?("phoenix_kit_defect_reasons")
      refute fk_exists?("phoenix_kit_machine_type_assignments", "machine_type_uuid")
      refute fk_exists?("phoenix_kit_machine_operations", "operation_uuid")

      assert %Entities{display_name: "Machine Type", display_name_plural: "Machine Types"} =
               machine_type_entity = Entities.get_entity_by_name("machine_type")

      assert %Entities{display_name: "Operation", display_name_plural: "Operations"} =
               operation_entity = Entities.get_entity_by_name("operation")

      assert %Entities{
               display_name: "Defect Reason",
               display_name_plural: "Defect Reasons"
             } = defect_reason_entity = Entities.get_entity_by_name("defect_reason")

      assert machine_type_entity.icon == "hero-tag"
      assert operation_entity.icon == "hero-clock"
      assert defect_reason_entity.icon == "hero-exclamation-triangle"

      # Fresh host — no legacy rows existed to migrate.
      assert EntityData.list_by_entity(machine_type_entity.uuid) == []
      assert EntityData.list_by_entity(operation_entity.uuid) == []
      assert EntityData.list_by_entity(defect_reason_entity.uuid) == []
    end
  end

  describe "up/1 (V5 — migrating a V4 host's legacy data)" do
    # Emulates a pre-V5 host: recreates the three legacy directory tables
    # (dropped from `public` by the cumulative up/1 test_helper.exs already
    # ran) via raw SQL — not the deleted-in-a-later-commit Ecto schemas, for
    # the same reason `Migrations.Machines` itself reads them via raw SQL
    # (see its moduledoc) — seeds a couple of rows per table (one
    # multilang, one flat/non-multilang, mirroring a host that never had
    # the Languages module enabled), links them from
    # `phoenix_kit_machine_type_assignments`/`phoenix_kit_machine_operations`,
    # and re-adds the FK constraints V5 is supposed to drop so the test
    # actually exercises `drop_fk_constraint/4` instead of it silently
    # no-op'ing against columns that were never constrained in the first
    # place (the regression review point #1 guards against).
    setup do
      {:ok, machine} =
        PhoenixKitManufacturing.Machines.create_machine(%{name: "Legacy Host Machine"})

      create_legacy_directory_tables!()

      type_a =
        insert_legacy_machine_type!(
          "Lathe",
          "Metal lathe (flat column — ignored, this row's data is multilang)",
          "active",
          %{
            "_primary_language" => "en-US",
            "en-US" => %{"_name" => "Lathe", "_description" => "Metal lathe"},
            "ru" => %{"_name" => "Токарный станок"}
          },
          [%{"key" => "power_kw", "label" => "Power (kW)", "type" => "number"}]
        )

      type_b = insert_legacy_machine_type!("Mill", "Milling machine", "inactive", %{}, [])

      operation_a =
        insert_legacy_operation!("Cutting", "pcs", 120, "active", %{
          "_primary_language" => "en-US",
          "en-US" => %{"_name" => "Cutting"},
          "et" => %{"_name" => "Lõikamine"}
        })

      operation_b =
        insert_legacy_operation!("Idle", nil, nil, "inactive", %{
          "_primary_language" => "en-US",
          "en-US" => %{"_name" => "Idle"}
        })

      defect_reason_a =
        insert_legacy_defect_reason!("Scratch", "Surface scratch", "active", %{
          "_primary_language" => "en-US",
          "en-US" => %{"_name" => "Scratch", "_description" => "Surface scratch"},
          "ru" => %{"_name" => "Царапина"}
        })

      insert_machine_type_assignment!(machine.uuid, type_a)
      insert_machine_type_assignment!(machine.uuid, type_b)
      insert_machine_operation!(machine.uuid, operation_a, 45)
      insert_machine_operation!(machine.uuid, operation_b, nil)

      %{
        machine: machine,
        type_a: type_a,
        type_b: type_b,
        operation_a: operation_a,
        operation_b: operation_b,
        defect_reason_a: defect_reason_a
      }
    end

    test "migrates every legacy row, converts multilang data, maps status, and rewires the join tables",
         %{
           machine: machine,
           type_a: type_a,
           type_b: type_b,
           operation_a: operation_a,
           operation_b: operation_b,
           defect_reason_a: defect_reason_a
         } do
      apply_v5_migration!()

      machine_type_entity = Entities.get_entity_by_name("machine_type")
      operation_entity = Entities.get_entity_by_name("operation")
      defect_reason_entity = Entities.get_entity_by_name("defect_reason")

      machine_type_records = EntityData.list_by_entity(machine_type_entity.uuid)
      operation_records = EntityData.list_by_entity(operation_entity.uuid)
      defect_reason_records = EntityData.list_by_entity(defect_reason_entity.uuid)

      assert length(machine_type_records) == 2
      assert length(operation_records) == 2
      assert length(defect_reason_records) == 1

      record_a1 = Enum.find(machine_type_records, &(&1.metadata["legacy_uuid"] == type_a))
      record_b1 = Enum.find(machine_type_records, &(&1.metadata["legacy_uuid"] == type_b))
      record_a2 = Enum.find(operation_records, &(&1.metadata["legacy_uuid"] == operation_a))
      record_b2 = Enum.find(operation_records, &(&1.metadata["legacy_uuid"] == operation_b))

      record_a3 =
        Enum.find(defect_reason_records, &(&1.metadata["legacy_uuid"] == defect_reason_a))

      assert record_a1, "expected a migrated machine_type record for legacy uuid #{type_a}"
      assert record_b1, "expected a migrated machine_type record for legacy uuid #{type_b}"
      assert record_a2, "expected a migrated operation record for legacy uuid #{operation_a}"
      assert record_b2, "expected a migrated operation record for legacy uuid #{operation_b}"

      assert record_a3,
             "expected a migrated defect_reason record for legacy uuid #{defect_reason_a}"

      # Multilang machine_type: "_name" -> "_title" in every lang block,
      # "_description" untouched, field_template moved to *metadata* (not
      # data — see review point #4) rather than lost.
      assert record_a1.title == "Lathe"
      assert record_a1.status == "published"

      assert record_a1.data == %{
               "_primary_language" => "en-US",
               "en-US" => %{"_title" => "Lathe", "_description" => "Metal lathe"},
               "ru" => %{"_title" => "Токарный станок"}
             }

      assert record_a1.metadata["field_template"] == [
               %{"key" => "power_kw", "label" => "Power (kW)", "type" => "number"}
             ]

      # Flat (non-multilang) machine_type: primary block built fresh from
      # the legacy flat name/description columns, keyed under whatever the
      # current primary language is (this test DB has no Languages module
      # configured, so `Multilang.primary_language/0`'s "en-US" fallback
      # applies — fetched dynamically rather than hardcoded).
      primary = Multilang.primary_language()

      assert record_b1.title == "Mill"
      assert record_b1.status == "draft"

      assert record_b1.data == %{
               "_primary_language" => primary,
               primary => %{"_title" => "Mill", "_description" => "Milling machine"}
             }

      assert record_b1.metadata["field_template"] == []

      # Multilang operation: unit/base_time_norm_seconds land unprefixed on
      # the primary block only (review point #2) — secondary blocks are
      # untouched, and operation records carry no field_template metadata.
      assert record_a2.title == "Cutting"
      assert record_a2.status == "published"

      assert record_a2.data == %{
               "_primary_language" => "en-US",
               "en-US" => %{
                 "_title" => "Cutting",
                 "unit" => "pcs",
                 "base_time_norm_seconds" => 120
               },
               "et" => %{"_title" => "Lõikamine"}
             }

      refute Map.has_key?(record_a2.metadata, "field_template")

      # Operation with nil unit/base_time_norm_seconds: neither key is
      # added to the primary block at all.
      assert record_b2.title == "Idle"
      assert record_b2.status == "draft"
      assert record_b2.data == %{"_primary_language" => "en-US", "en-US" => %{"_title" => "Idle"}}

      # defect_reason: plain multilang carry-over, no field_template.
      assert record_a3.title == "Scratch"
      assert record_a3.status == "published"

      assert record_a3.data == %{
               "_primary_language" => "en-US",
               "en-US" => %{"_title" => "Scratch", "_description" => "Surface scratch"},
               "ru" => %{"_title" => "Царапина"}
             }

      refute Map.has_key?(record_a3.metadata, "field_template")

      # Join tables rewired from the old (dropped) uuids to the new
      # entity_data uuids.
      assert MapSet.new(current_machine_type_uuids(machine.uuid)) ==
               MapSet.new([record_a1.uuid, record_b1.uuid])

      assert MapSet.new(current_operation_links(machine.uuid)) ==
               MapSet.new([{record_a2.uuid, 45}, {record_b2.uuid, nil}])

      # The three legacy tables and both FK constraints are gone again.
      refute table_exists?("phoenix_kit_machine_types")
      refute table_exists?("phoenix_kit_operations")
      refute table_exists?("phoenix_kit_defect_reasons")
      refute fk_exists?("phoenix_kit_machine_type_assignments", "machine_type_uuid")
      refute fk_exists?("phoenix_kit_machine_operations", "operation_uuid")
    end

    test "running up/1 twice does not duplicate records or corrupt the rewired references", %{
      machine: machine,
      type_a: type_a,
      type_b: type_b,
      operation_a: operation_a,
      operation_b: operation_b
    } do
      apply_v5_migration!()

      machine_type_entity = Entities.get_entity_by_name("machine_type")
      operation_entity = Entities.get_entity_by_name("operation")
      defect_reason_entity = Entities.get_entity_by_name("defect_reason")

      types_after_first = EntityData.list_by_entity(machine_type_entity.uuid)
      operations_after_first = EntityData.list_by_entity(operation_entity.uuid)
      defect_reasons_after_first = EntityData.list_by_entity(defect_reason_entity.uuid)
      type_uuids_after_first = MapSet.new(current_machine_type_uuids(machine.uuid))
      operation_links_after_first = MapSet.new(current_operation_links(machine.uuid))

      # Second call: `up/1` is cumulative, so this silently recreates the
      # three (now-empty, already-migrated) legacy tables, finds nothing
      # left to migrate (0 rows), and drops them again — a safe no-op (see
      # `Migrations.Machines`' moduledoc and review point #3).
      apply_v5_migration!()

      assert length(EntityData.list_by_entity(machine_type_entity.uuid)) ==
               length(types_after_first)

      assert length(EntityData.list_by_entity(operation_entity.uuid)) ==
               length(operations_after_first)

      assert length(EntityData.list_by_entity(defect_reason_entity.uuid)) ==
               length(defect_reasons_after_first)

      assert MapSet.new(current_machine_type_uuids(machine.uuid)) == type_uuids_after_first
      assert MapSet.new(current_operation_links(machine.uuid)) == operation_links_after_first

      # The legacy uuids still resolve to the *same* new records — the
      # mapping was recovered from `metadata->>legacy_uuid`, not rebuilt
      # from scratch and duplicated.
      types_by_legacy = Map.new(types_after_first, &{&1.metadata["legacy_uuid"], &1.uuid})
      assert MapSet.member?(type_uuids_after_first, types_by_legacy[type_a])
      assert MapSet.member?(type_uuids_after_first, types_by_legacy[type_b])

      operations_by_legacy =
        Map.new(operations_after_first, &{&1.metadata["legacy_uuid"], &1.uuid})

      assert MapSet.member?(operation_links_after_first, {operations_by_legacy[operation_a], 45})
      assert MapSet.member?(operation_links_after_first, {operations_by_legacy[operation_b], nil})

      refute table_exists?("phoenix_kit_machine_types")
      refute table_exists?("phoenix_kit_operations")
      refute table_exists?("phoenix_kit_defect_reasons")
    end
  end

  describe "down/1" do
    test "unconditionally raises and never touches the database" do
      assert %Entities{} = Entities.get_entity_by_name("machine_type")
      assert %Entities{} = Entities.get_entity_by_name("operation")
      assert %Entities{} = Entities.get_entity_by_name("defect_reason")

      assert_raise RuntimeError, ~r/rollback is not supported/, fn ->
        Machines.down(prefix: "public")
      end

      # Nothing was touched — the blueprint entities are still there and
      # the (already-dropped, on a V5 host) legacy tables stay dropped.
      assert %Entities{} = Entities.get_entity_by_name("machine_type")
      assert %Entities{} = Entities.get_entity_by_name("operation")
      assert %Entities{} = Entities.get_entity_by_name("defect_reason")
      refute table_exists?("phoenix_kit_machine_types")
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

  # Mirrors the catalog lookup `Migrations.Machines`' private
  # `fk_constraint_name/3` uses — that helper isn't exported, so the query
  # is duplicated here, same as `table_exists?/1` and `column_exists?/2`
  # above already duplicate their migration-module counterparts.
  defp fk_exists?(table, column) do
    query = """
    SELECT 1
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND tc.table_name = $1
      AND kcu.column_name = $2
    """

    case Repo.query(query, [table, column]) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  end

  # Re-applies `Migrations.Machines.up/1` through the same
  # `Ecto.Migrator.up/4` + static wrapper module path test_helper.exs uses
  # for the suite's initial migration — `Machines.up/1` calls
  # `Ecto.Migration.execute/1` internally, which needs a live
  # `Ecto.Migration.Runner` process, not just a plain function call. A
  # fresh microsecond version on every call means each invocation actually
  # runs (never short-circuits on "already up").
  defp apply_v5_migration! do
    assert Ecto.Migrator.up(
             Repo,
             System.os_time(:microsecond),
             PhoenixKitManufacturing.Test.MachinesMigration,
             log: false
           ) == :ok
  end

  # ── V4-host seeding helpers ──
  #
  # Raw SQL throughout, not the module's own Ecto schemas (`Schemas.MachineType`
  # etc.) — those are deleted from the codebase in a later commit of this
  # wave, and `Migrations.Machines` itself is specifically designed to
  # never depend on them still existing (see its moduledoc). Column shapes
  # match the final (V4) shape `Migrations.Machines.up/1` creates.

  defp create_legacy_directory_tables! do
    Repo.query!("""
    CREATE TABLE phoenix_kit_machine_types (
      uuid UUID PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      description TEXT,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      data JSONB NOT NULL DEFAULT '{}',
      field_template JSONB NOT NULL DEFAULT '[]',
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """)

    Repo.query!("""
    CREATE TABLE phoenix_kit_operations (
      uuid UUID PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      unit VARCHAR(50),
      base_time_norm_seconds INTEGER,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      data JSONB NOT NULL DEFAULT '{}',
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """)

    Repo.query!("""
    CREATE TABLE phoenix_kit_defect_reasons (
      uuid UUID PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      description TEXT,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      data JSONB NOT NULL DEFAULT '{}',
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """)

    # Re-add the FK constraints a real V4 host would still have, so this
    # test exercises `drop_fk_constraint/4` actually finding and dropping
    # something (the FK-before-rewire ordering review point #1 guards
    # against would otherwise go untested — with no FK present, the rewire
    # UPDATE can't ever hit a foreign-key violation regardless of step
    # order).
    Repo.query!("""
    ALTER TABLE phoenix_kit_machine_type_assignments
    ADD FOREIGN KEY (machine_type_uuid)
    REFERENCES phoenix_kit_machine_types (uuid) ON DELETE CASCADE
    """)

    Repo.query!("""
    ALTER TABLE phoenix_kit_machine_operations
    ADD FOREIGN KEY (operation_uuid)
    REFERENCES phoenix_kit_operations (uuid) ON DELETE CASCADE
    """)

    :ok
  end

  defp insert_legacy_machine_type!(name, description, status, data, field_template) do
    uuid = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO phoenix_kit_machine_types (uuid, name, description, status, data, field_template)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb)
      """,
      [
        Ecto.UUID.dump!(uuid),
        name,
        description,
        status,
        Jason.encode!(data),
        Jason.encode!(field_template)
      ]
    )

    uuid
  end

  defp insert_legacy_operation!(name, unit, base_time_norm_seconds, status, data) do
    uuid = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO phoenix_kit_operations
        (uuid, name, unit, base_time_norm_seconds, status, data)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb)
      """,
      [Ecto.UUID.dump!(uuid), name, unit, base_time_norm_seconds, status, Jason.encode!(data)]
    )

    uuid
  end

  defp insert_legacy_defect_reason!(name, description, status, data) do
    uuid = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO phoenix_kit_defect_reasons (uuid, name, description, status, data)
      VALUES ($1, $2, $3, $4, $5::jsonb)
      """,
      [Ecto.UUID.dump!(uuid), name, description, status, Jason.encode!(data)]
    )

    uuid
  end

  defp insert_machine_type_assignment!(machine_uuid, machine_type_uuid) do
    Repo.query!(
      """
      INSERT INTO phoenix_kit_machine_type_assignments (machine_uuid, machine_type_uuid)
      VALUES ($1, $2)
      """,
      [Ecto.UUID.dump!(machine_uuid), Ecto.UUID.dump!(machine_type_uuid)]
    )

    :ok
  end

  defp insert_machine_operation!(machine_uuid, operation_uuid, time_norm_seconds) do
    Repo.query!(
      """
      INSERT INTO phoenix_kit_machine_operations (machine_uuid, operation_uuid, time_norm_seconds)
      VALUES ($1, $2, $3)
      """,
      [Ecto.UUID.dump!(machine_uuid), Ecto.UUID.dump!(operation_uuid), time_norm_seconds]
    )

    :ok
  end

  defp current_machine_type_uuids(machine_uuid) do
    %Postgrex.Result{rows: rows} =
      Repo.query!(
        "SELECT machine_type_uuid FROM phoenix_kit_machine_type_assignments WHERE machine_uuid = $1",
        [Ecto.UUID.dump!(machine_uuid)]
      )

    Enum.map(rows, fn [uuid_bin] -> Ecto.UUID.load!(uuid_bin) end)
  end

  defp current_operation_links(machine_uuid) do
    %Postgrex.Result{rows: rows} =
      Repo.query!(
        """
        SELECT operation_uuid, time_norm_seconds FROM phoenix_kit_machine_operations
        WHERE machine_uuid = $1
        """,
        [Ecto.UUID.dump!(machine_uuid)]
      )

    Enum.map(rows, fn [uuid_bin, time_norm] -> {Ecto.UUID.load!(uuid_bin), time_norm} end)
  end
end
