defmodule PhoenixKitManufacturing.OperationsTest do
  # Integration tests for the context — require PostgreSQL, excluded when
  # the DB is unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.DataCase, async: true

  alias PhoenixKitManufacturing.Operations
  alias PhoenixKitManufacturing.Schemas.{MachineOperation, Operation}

  describe "operations" do
    test "create/list/count/get/update/delete round-trip" do
      assert Operations.count_operations() == 0

      {:ok, %Operation{} = cutting} =
        Operations.create_operation(%{name: "Cutting", unit: "pcs"})

      assert cutting.status == "active"
      assert Operations.count_operations() == 1
      assert [%Operation{name: "Cutting"}] = Operations.list_operations()
      assert %Operation{name: "Cutting"} = Operations.get_operation(cutting.uuid)
      assert %Operation{name: "Cutting"} = Operations.get_operation_by_name("Cutting")

      {:ok, updated} = Operations.update_operation(cutting, %{status: "inactive"})
      assert updated.status == "inactive"

      {:ok, _} = Operations.delete_operation(cutting)
      assert Operations.count_operations() == 0
    end

    test "list_operations/1 and count_operations/1 filter by status" do
      {:ok, _} = Operations.create_operation(%{name: "Active", status: "active"})
      {:ok, _} = Operations.create_operation(%{name: "Inactive", status: "inactive"})

      assert [%Operation{name: "Active"}] = Operations.list_operations(status: "active")
      assert Operations.count_operations(status: "active") == 1
      assert Operations.count_operations(status: "inactive") == 1
    end

    test "list_operations/0 orders by name" do
      {:ok, _} = Operations.create_operation(%{name: "Welding"})
      {:ok, _} = Operations.create_operation(%{name: "Assembly"})
      {:ok, _} = Operations.create_operation(%{name: "Cutting"})

      assert Enum.map(Operations.list_operations(), & &1.name) == [
               "Assembly",
               "Cutting",
               "Welding"
             ]
    end

    test "get_operation/1 and get_operation_by_name/1 return nil when not found" do
      assert Operations.get_operation(Ecto.UUID.generate()) == nil
      assert Operations.get_operation_by_name("Nonexistent") == nil
    end

    test "create_operation/2 returns a changeset error on a blank name" do
      assert {:error, changeset} = Operations.create_operation(%{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "change_operation/2 returns an unsaved changeset" do
      changeset = Operations.change_operation(%Operation{}, %{name: "Cutting"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.data == %Operation{}
    end

    # Exercises the `ON DELETE CASCADE` FK declared in the V3 migration
    # (`migrations/machines.ex`) directly at the schema level — the
    # machine-side linking API (sync/list/has_operation?) is
    # `Machines`'s "Machine ↔ Operation linking" section, a later task, so
    # this inserts the join row directly rather than depending on it.
    test "deleting an operation cascades to its machine links" do
      {:ok, machine} = PhoenixKitManufacturing.Machines.create_machine(%{name: "CNC-01"})
      {:ok, cutting} = Operations.create_operation(%{name: "Cutting"})

      %MachineOperation{}
      |> MachineOperation.changeset(%{machine_uuid: machine.uuid, operation_uuid: cutting.uuid})
      |> Repo.insert!()

      {:ok, _} = Operations.delete_operation(cutting)

      assert Repo.all(from(mo in MachineOperation, where: mo.operation_uuid == ^cutting.uuid)) ==
               []
    end
  end

  describe "activity logging" do
    test "records operation.created with the actor and metadata" do
      actor = Ecto.UUID.generate()

      {:ok, operation} =
        Operations.create_operation(%{name: "Cutting", unit: "pcs"}, actor_uuid: actor)

      assert_activity_logged("operation.created",
        actor_uuid: actor,
        resource_uuid: operation.uuid,
        metadata_has: %{"name" => "Cutting", "status" => "active"}
      )
    end

    test "does not log when no actor is given for a successful create" do
      {:ok, _} = Operations.create_operation(%{name: "Anon"})
      # A log row is still written (actor_uuid nil); assert it carries the module key.
      row = assert_activity_logged("operation.created", metadata_has: %{"name" => "Anon"})
      assert row.module == "manufacturing"
    end

    test "records operation.updated on a successful update" do
      {:ok, operation} = Operations.create_operation(%{name: "Cutting"})
      actor = Ecto.UUID.generate()

      {:ok, _} = Operations.update_operation(operation, %{status: "inactive"}, actor_uuid: actor)

      assert_activity_logged("operation.updated",
        actor_uuid: actor,
        resource_uuid: operation.uuid,
        metadata_has: %{"status" => "inactive"}
      )
    end

    test "records operation.deleted on a successful delete" do
      {:ok, operation} = Operations.create_operation(%{name: "Cutting"})
      actor = Ecto.UUID.generate()

      {:ok, _} = Operations.delete_operation(operation, actor_uuid: actor)

      assert_activity_logged("operation.deleted",
        actor_uuid: actor,
        resource_uuid: operation.uuid
      )
    end

    test "logs a db_pending row when create fails validation" do
      actor = Ecto.UUID.generate()
      {:error, _changeset} = Operations.create_operation(%{name: ""}, actor_uuid: actor)

      assert_activity_logged("operation.created",
        actor_uuid: actor,
        metadata_has: %{"db_pending" => true, "error_fields" => ["name"]}
      )
    end
  end
end
