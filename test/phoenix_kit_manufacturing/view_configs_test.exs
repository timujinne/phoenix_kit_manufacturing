defmodule PhoenixKitManufacturing.ViewConfigsTest do
  # Backed by PhoenixKit.Settings (core's phoenix_kit_settings table) —
  # requires PostgreSQL, excluded when the DB is unavailable.
  use PhoenixKitManufacturing.DataCase, async: false

  alias PhoenixKitManufacturing.ViewConfigs

  test "get_view_config/2 returns %{} when nothing saved yet" do
    assert ViewConfigs.get_view_config(
             "00000000-0000-0000-0000-000000000001",
             "manufacturing_machines"
           ) ==
             %{}
  end

  test "merge_view_config/3 persists and round-trips" do
    uuid = "00000000-0000-0000-0000-000000000002"

    assert {:ok, %{"columns" => ["name", "status"]}} =
             ViewConfigs.merge_view_config(uuid, "manufacturing_machines", %{
               "columns" => ["name", "status"]
             })

    assert ViewConfigs.get_view_config(uuid, "manufacturing_machines") == %{
             "columns" => ["name", "status"]
           }
  end

  test "merge_view_config/3 preserves keys not touched by a later merge" do
    uuid = "00000000-0000-0000-0000-000000000003"

    {:ok, _} =
      ViewConfigs.merge_view_config(uuid, "manufacturing_machines", %{
        "columns" => ["name", "status"]
      })

    {:ok, merged} =
      ViewConfigs.merge_view_config(uuid, "manufacturing_machines", %{
        "active_filters" => ["status"]
      })

    assert merged == %{"columns" => ["name", "status"], "active_filters" => ["status"]}
  end

  test "scopes are independent for the same user" do
    uuid = "00000000-0000-0000-0000-000000000004"

    {:ok, _} =
      ViewConfigs.merge_view_config(uuid, "manufacturing_machines", %{
        "columns" => ["name"]
      })

    assert ViewConfigs.get_view_config(uuid, "manufacturing_operations") == %{}
  end
end
