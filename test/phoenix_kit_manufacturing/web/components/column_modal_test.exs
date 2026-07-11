defmodule PhoenixKitManufacturing.Web.Components.ColumnModalTest do
  # Pure function component — no DB, no endpoint/router needed.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias PhoenixKitManufacturing.ColumnConfig.Machines, as: ColumnConfig
  alias PhoenixKitManufacturing.Web.Components.ColumnModal

  defp base_assigns(overrides) do
    Map.merge(
      %{
        show: true,
        column_config: ColumnConfig,
        selected: ["name", "code"],
        active_filters: []
      },
      overrides
    )
  end

  test "renders nothing when show is false" do
    html = render_component(&ColumnModal.column_modal/1, base_assigns(%{show: false}))

    refute html =~ "Customize columns"
  end

  test "renders the modal with selected and available columns split" do
    html = render_component(&ColumnModal.column_modal/1, base_assigns(%{}))

    assert html =~ "Customize columns"
    # Selected columns (labels from ColumnConfig.Machines).
    assert html =~ "Name"
    assert html =~ "Code"
    # Available (not yet selected) columns show up on the right.
    assert html =~ "Manufacturer"
    assert html =~ "Model"
  end

  test "shows the empty state when no columns are selected" do
    html = render_component(&ColumnModal.column_modal/1, base_assigns(%{selected: []}))

    assert html =~ "No columns selected"
  end

  test "shows the 'all selected' state when every column is selected" do
    html =
      render_component(
        &ColumnModal.column_modal/1,
        base_assigns(%{selected: ColumnConfig.all_column_ids()})
      )

    assert html =~ "All columns selected"
  end

  test "filterable selected columns expose a filter toggle button" do
    html = render_component(&ColumnModal.column_modal/1, base_assigns(%{selected: ["name"]}))

    assert html =~ ~s(phx-click="toggle_filter")
    assert html =~ ~s(phx-value-column_id="name")
    assert html =~ "Enable filter"
  end

  test "an active filter on a selected column shows the disable-filter title" do
    html =
      render_component(
        &ColumnModal.column_modal/1,
        base_assigns(%{selected: ["name"], active_filters: ["name"]})
      )

    assert html =~ "Disable filter"
  end

  test "temp_selected/temp_active_filters override selected/active_filters when present" do
    html =
      render_component(
        &ColumnModal.column_modal/1,
        base_assigns(%{
          selected: ["name", "code"],
          active_filters: ["name"],
          temp_selected: [],
          temp_active_filters: []
        })
      )

    assert html =~ "No columns selected"
  end

  test "add/remove/reorder wiring is present on rendered rows" do
    html = render_component(&ColumnModal.column_modal/1, base_assigns(%{selected: ["name"]}))

    assert html =~ ~s(phx-click="remove_column")
    assert html =~ ~s(phx-submit="update_table_columns")
    assert html =~ ~s(phx-click="reset_to_defaults")
    assert html =~ ~s(phx-click="hide_column_modal")
    assert html =~ ~s(phx-click="add_column")
  end
end
