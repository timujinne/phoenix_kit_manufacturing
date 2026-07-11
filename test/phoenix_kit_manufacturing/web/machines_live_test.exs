defmodule PhoenixKitManufacturing.Web.MachinesLiveTest do
  # Integration tests — require PostgreSQL, excluded when the DB is
  # unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.LiveCase

  alias PhoenixKitManufacturing.{Machines, Operations}

  describe "list pages" do
    test "machines list renders the empty state", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines")
      assert html =~ "No machines yet."
    end

    test "types list renders the empty state", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines/types")
      assert html =~ "No machine types yet."
    end

    test "operations list renders the empty state", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines/operations")
      assert html =~ "No operations yet."
    end

    test "an existing operation appears in the list with its unit and formatted base norm", %{
      conn: conn
    } do
      {:ok, _op} =
        Operations.create_operation(%{name: "Cutting", unit: "pcs", base_time_norm_seconds: 125})

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines/operations")

      assert html =~ "Cutting"
      assert html =~ "pcs"
      assert html =~ "00:02:05"
    end

    test "an operation without a base norm renders an em dash", %{conn: conn} do
      {:ok, _op} = Operations.create_operation(%{name: "Inspection"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines/operations")

      assert html =~ "Inspection"
      assert html =~ "—"
    end

    test "an existing machine appears in the list", %{conn: conn} do
      {:ok, _m} = Machines.create_machine(%{name: "CNC-01"})
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines")
      assert html =~ "CNC-01"
    end

    test "the repair and mothballed statuses render their labels", %{conn: conn} do
      {:ok, _m1} = Machines.create_machine(%{name: "Press-02", status: "repair"})
      {:ok, _m2} = Machines.create_machine(%{name: "Old Lathe", status: "mothballed"})
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines")

      assert html =~ "Repair"
      assert html =~ "Mothballed"
    end

    test "a machine's location note appears in the Location column", %{conn: conn} do
      {:ok, _m} =
        Machines.create_machine(%{name: "Router-03", location_note: "Shop Floor A"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines")

      assert html =~ "Shop Floor A"
    end

    test "a machine's type name appears as a badge in the Types column", %{conn: conn} do
      {:ok, type} = Machines.create_machine_type(%{name: "Laser"})
      {:ok, machine} = Machines.create_machine(%{name: "Laser-01"})
      {:ok, _} = Machines.sync_machine_types(machine.uuid, [type.uuid])

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/manufacturing/machines")

      assert html =~ "Laser-01"
      assert html =~ "Laser"
    end
  end

  describe "global search" do
    test "search by machine name narrows the list", %{conn: conn} do
      {:ok, _m1} = Machines.create_machine(%{name: "CNC Mill"})
      {:ok, _m2} = Machines.create_machine(%{name: "Laser Cutter"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines")

      html = render_change(view, "search", %{"search" => "laser"})

      assert html =~ "Laser Cutter"
      refute html =~ "CNC Mill"
    end

    test "empty search returns all machines", %{conn: conn} do
      {:ok, _m1} = Machines.create_machine(%{name: "CNC Mill"})
      {:ok, _m2} = Machines.create_machine(%{name: "Laser Cutter"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines")

      html = render_change(view, "search", %{"search" => ""})

      assert html =~ "CNC Mill"
      assert html =~ "Laser Cutter"
    end
  end

  describe "sort" do
    test "flipping sort direction reverses the list order", %{conn: conn} do
      {:ok, _} = Machines.create_machine(%{name: "Alpha"})
      {:ok, _} = Machines.create_machine(%{name: "Zeta"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, html_asc} = live(conn, "/en/admin/manufacturing/machines")

      # Default is ascending by name — Alpha before Zeta
      asc_pos_alpha = :binary.match(html_asc, "Alpha") |> elem(0)
      asc_pos_zeta = :binary.match(html_asc, "Zeta") |> elem(0)
      assert asc_pos_alpha < asc_pos_zeta

      html_desc = render_click(view, "flip_sort_dir", %{})

      desc_pos_alpha = :binary.match(html_desc, "Alpha") |> elem(0)
      desc_pos_zeta = :binary.match(html_desc, "Zeta") |> elem(0)
      assert desc_pos_zeta < desc_pos_alpha
    end
  end

  describe "machine form" do
    test "creating a machine redirects to the list and persists it", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("form", machine: %{name: "New Mill", status: "active"})
               |> render_submit()

      assert to =~ "manufacturing/machines"
      assert [%{name: "New Mill"}] = Machines.list_machines()
    end

    test "an invalid submit re-renders the form with an error", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines/new")

      html =
        view
        |> form("form", machine: %{name: "", status: "active"})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      assert Machines.count_machines() == 0
    end
  end

  describe "delete flow" do
    test "deleting a machine removes it from the list", %{conn: conn} do
      {:ok, machine} = Machines.create_machine(%{name: "To Delete"})
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines")

      view
      |> element(~s{button[phx-value-uuid="#{machine.uuid}"][phx-value-type="machine"]})
      |> render_click()

      html = render_click(view, "delete_machine", %{})
      assert html =~ "No machines yet."
      assert Machines.count_machines() == 0
    end

    test "deleting an operation removes it from the list", %{conn: conn} do
      {:ok, operation} = Operations.create_operation(%{name: "To Delete"})
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines/operations")

      view
      |> element(~s{button[phx-value-uuid="#{operation.uuid}"][phx-value-type="operation"]})
      |> render_click()

      html = render_click(view, "delete_operation", %{})
      assert html =~ "No operations yet."
      assert Operations.count_operations() == 0
    end

    test "cancelling an operation delete leaves it in the list", %{conn: conn} do
      {:ok, operation} = Operations.create_operation(%{name: "Keep Me"})
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines/operations")

      view
      |> element(~s{button[phx-value-uuid="#{operation.uuid}"][phx-value-type="operation"]})
      |> render_click()

      html = render_click(view, "cancel_delete", %{})
      assert html =~ "Keep Me"
      assert Operations.count_operations() == 1
    end
  end

  # Web.ColumnManagement's event handlers (add_column, toggle_filter,
  # update_table_columns, set_filter_value, clear_all_filters) have no
  # dedicated test file of their own — covered here end-to-end through
  # MachinesLive, the only current consumer.
  describe "column customization and filters" do
    test "filtering by status narrows the list to matching machines", %{conn: conn} do
      {:ok, _} = Machines.create_machine(%{name: "Healthy Mill", status: "active"})
      {:ok, _} = Machines.create_machine(%{name: "Broken Press", status: "repair"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines")

      # "status" is a default column, so toggle_filter works without an
      # add_column step first.
      render_click(view, "show_column_modal", %{})
      render_click(view, "toggle_filter", %{"column_id" => "status"})
      render_submit(view, "update_table_columns", %{})

      html =
        render_change(view, "set_filter_value", %{"column_id" => "status", "value" => "repair"})

      assert html =~ "Broken Press"
      refute html =~ "Healthy Mill"
    end

    test "clear_all_filters restores the full list", %{conn: conn} do
      {:ok, _} = Machines.create_machine(%{name: "Healthy Mill", status: "active"})
      {:ok, _} = Machines.create_machine(%{name: "Broken Press", status: "repair"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/manufacturing/machines")

      render_click(view, "show_column_modal", %{})
      render_click(view, "toggle_filter", %{"column_id" => "status"})
      render_submit(view, "update_table_columns", %{})
      render_change(view, "set_filter_value", %{"column_id" => "status", "value" => "repair"})

      html = render_click(view, "clear_all_filters", %{})

      assert html =~ "Broken Press"
      assert html =~ "Healthy Mill"
    end

    test "adding a column via the modal persists across a reload for the same user", %{
      conn: conn
    } do
      scope = fake_scope()
      {:ok, _} = Machines.create_machine(%{name: "CNC-01", manufacturer: "Haas"})

      conn1 = put_test_scope(conn, scope)
      {:ok, view, html} = live(conn1, "/en/admin/manufacturing/machines")
      refute html =~ "Manufacturer"

      render_click(view, "show_column_modal", %{})
      render_click(view, "add_column", %{"column_id" => "manufacturer"})

      html =
        render_submit(view, "update_table_columns", %{
          "column_order" => "name,code,status,location,types,manufacturer"
        })

      assert html =~ "Manufacturer"

      conn2 =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> put_test_scope(scope)

      {:ok, _view2, html2} = live(conn2, "/en/admin/manufacturing/machines")
      assert html2 =~ "Manufacturer"
    end
  end
end
