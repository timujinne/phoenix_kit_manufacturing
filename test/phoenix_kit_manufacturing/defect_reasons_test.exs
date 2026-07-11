defmodule PhoenixKitManufacturing.DefectReasonsTest do
  # Integration tests for the context — require PostgreSQL, excluded when
  # the DB is unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.DataCase, async: true

  alias PhoenixKitManufacturing.DefectReasons
  alias PhoenixKitManufacturing.Schemas.DefectReason

  describe "defect_reasons" do
    test "create/list/count/get/update/delete round-trip" do
      assert DefectReasons.count_defect_reasons() == 0

      {:ok, %DefectReason{} = scratch} =
        DefectReasons.create_defect_reason(%{name: "Scratched surface"})

      assert scratch.status == "active"
      assert DefectReasons.count_defect_reasons() == 1
      assert [%DefectReason{name: "Scratched surface"}] = DefectReasons.list_defect_reasons()

      assert %DefectReason{name: "Scratched surface"} =
               DefectReasons.get_defect_reason(scratch.uuid)

      {:ok, updated} = DefectReasons.update_defect_reason(scratch, %{status: "inactive"})
      assert updated.status == "inactive"

      {:ok, _} = DefectReasons.delete_defect_reason(scratch)
      assert DefectReasons.count_defect_reasons() == 0
    end

    test "list_defect_reasons/1 and count_defect_reasons/1 filter by status" do
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Active", status: "active"})
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Inactive", status: "inactive"})

      assert [%DefectReason{name: "Active"}] = DefectReasons.list_defect_reasons(status: "active")
      assert DefectReasons.count_defect_reasons(status: "active") == 1
      assert DefectReasons.count_defect_reasons(status: "inactive") == 1
    end

    test "list_defect_reasons/0 orders by name" do
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Wrong dimensions"})
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Missing part"})
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Cosmetic damage"})

      assert Enum.map(DefectReasons.list_defect_reasons(), & &1.name) == [
               "Cosmetic damage",
               "Missing part",
               "Wrong dimensions"
             ]
    end

    test "get_defect_reason/1 returns nil when not found" do
      assert DefectReasons.get_defect_reason(Ecto.UUID.generate()) == nil
    end

    test "create_defect_reason/2 returns a changeset error on a blank name" do
      assert {:error, changeset} = DefectReasons.create_defect_reason(%{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "change_defect_reason/2 returns an unsaved changeset" do
      changeset =
        DefectReasons.change_defect_reason(%DefectReason{}, %{name: "Scratched surface"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.data == %DefectReason{}
    end
  end

  describe "activity logging" do
    test "records defect_reason.created with the actor and metadata" do
      actor = Ecto.UUID.generate()

      {:ok, defect_reason} =
        DefectReasons.create_defect_reason(%{name: "Scratched surface"}, actor_uuid: actor)

      assert_activity_logged("defect_reason.created",
        actor_uuid: actor,
        resource_uuid: defect_reason.uuid,
        metadata_has: %{"name" => "Scratched surface", "status" => "active"}
      )
    end

    test "does not log when no actor is given for a successful create" do
      {:ok, _} = DefectReasons.create_defect_reason(%{name: "Anon"})
      # A log row is still written (actor_uuid nil); assert it carries the module key.
      row = assert_activity_logged("defect_reason.created", metadata_has: %{"name" => "Anon"})
      assert row.module == "manufacturing"
    end

    test "records defect_reason.updated on a successful update" do
      {:ok, defect_reason} = DefectReasons.create_defect_reason(%{name: "Scratched surface"})
      actor = Ecto.UUID.generate()

      {:ok, _} =
        DefectReasons.update_defect_reason(defect_reason, %{status: "inactive"},
          actor_uuid: actor
        )

      assert_activity_logged("defect_reason.updated",
        actor_uuid: actor,
        resource_uuid: defect_reason.uuid,
        metadata_has: %{"status" => "inactive"}
      )
    end

    test "records defect_reason.deleted on a successful delete" do
      {:ok, defect_reason} = DefectReasons.create_defect_reason(%{name: "Scratched surface"})
      actor = Ecto.UUID.generate()

      {:ok, _} = DefectReasons.delete_defect_reason(defect_reason, actor_uuid: actor)

      assert_activity_logged("defect_reason.deleted",
        actor_uuid: actor,
        resource_uuid: defect_reason.uuid
      )
    end

    test "logs a db_pending row when create fails validation" do
      actor = Ecto.UUID.generate()
      {:error, _changeset} = DefectReasons.create_defect_reason(%{name: ""}, actor_uuid: actor)

      assert_activity_logged("defect_reason.created",
        actor_uuid: actor,
        metadata_has: %{"db_pending" => true, "error_fields" => ["name"]}
      )
    end
  end
end
