defmodule PhoenixKitManufacturing.Web.MachineTypeFormLiveTest do
  # Integration tests — require PostgreSQL, excluded when the DB is
  # unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.LiveCase

  alias PhoenixKitManufacturing.Machines

  defp new_path, do: "/en/admin/manufacturing/machines/types/new"
  defp edit_path(type), do: "/en/admin/manufacturing/machines/types/#{type.uuid}/edit"

  describe "add_field_row / remove_field_row" do
    test "a new type starts with no rows and shows the empty-state hint", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, new_path())

      refute html =~ "machine_type[field_template]"
      assert html =~ "No fields yet"
    end

    test "add_field_row appends an empty row named by index", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      html = render_click(view, "add_field_row", %{})

      assert html =~ "machine_type[field_template][0][key]"
      assert html =~ "machine_type[field_template][0][label]"
      assert html =~ "machine_type[field_template][0][type]"
      assert html =~ "machine_type[field_template][0][unit]"
      assert html =~ "machine_type[field_template][0][required]"
      # Fresh rows default to type "text" — no Options input until "select".
      refute html =~ "machine_type[field_template][0][options]"
    end

    test "add_field_row twice appends rows at increasing indices", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})
      html = render_click(view, "add_field_row", %{})

      assert html =~ "machine_type[field_template][0][key]"
      assert html =~ "machine_type[field_template][1][key]"
    end

    test "remove_field_row deletes the row at that index and the rest re-index", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})
      render_click(view, "add_field_row", %{})
      html = render_click(view, "add_field_row", %{})
      assert html =~ "machine_type[field_template][2][key]"

      html = render_click(view, "remove_field_row", %{"index" => "1"})

      assert %{field_template_rows: rows} = :sys.get_state(view.pid).socket.assigns
      assert length(rows) == 2

      assert html =~ "machine_type[field_template][0][key]"
      assert html =~ "machine_type[field_template][1][key]"
      refute html =~ "machine_type[field_template][2][key]"
    end
  end

  describe "loading an existing field_template on :edit" do
    test "pre-populates rows, with the Options input only on the select row", %{conn: conn} do
      {:ok, type} =
        Machines.create_machine_type(%{
          name: "CNC",
          field_template: [
            %{
              "key" => "power_kw",
              "label" => "Power",
              "type" => "number",
              "unit" => "kW",
              "required" => true
            },
            %{
              "key" => "voltage",
              "label" => "Voltage",
              "type" => "select",
              "options" => ["110V", "220V"]
            }
          ]
        })

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, html} = live(conn, edit_path(type))

      assert html =~ ~s(machine_type[field_template][0][key])
      assert html =~ ~s(value="power_kw")
      assert html =~ ~s(value="Power")
      assert html =~ ~s(value="kW")

      assert has_element?(
               view,
               "input[name='machine_type[field_template][0][required]'][checked]"
             )

      refute has_element?(
               view,
               "input[name='machine_type[field_template][1][required]'][checked]"
             )

      # Row 0 is "number" — no Options input; row 1 is "select" — has one,
      # pre-filled from the stored list joined back into display text.
      refute html =~ "machine_type[field_template][0][options]"
      assert html =~ "machine_type[field_template][1][options]"
      assert html =~ "110V, 220V"
    end
  end

  describe "field_template row editing via validate" do
    test "switching a row's type to \"select\" reveals the Options input", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})
      refute render(view) =~ "machine_type[field_template][0][options]"

      html =
        render_change(view, "validate", %{
          "machine_type" => %{
            "name" => "CNC",
            "field_template" => %{
              "0" => %{
                "key" => "voltage",
                "label" => "Voltage",
                "type" => "select",
                "unit" => "",
                "required" => "false",
                "options" => ""
              }
            }
          }
        })

      assert html =~ "machine_type[field_template][0][options]"
    end
  end

  describe "save" do
    test "persists rows added through the editor (number+required, select+options, trimmed)", %{
      conn: conn
    } do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})
      render_click(view, "add_field_row", %{})

      assert {:error, {:live_redirect, _}} =
               render_submit(view, "save", %{
                 "machine_type" => %{
                   "name" => "CNC",
                   "field_template" => %{
                     "0" => %{
                       "key" => " power_kw ",
                       "label" => " Power ",
                       "type" => "number",
                       "unit" => " kW ",
                       "required" => "true",
                       "options" => ""
                     },
                     "1" => %{
                       "key" => "voltage",
                       "label" => "Voltage",
                       "type" => "select",
                       "unit" => "",
                       "required" => "false",
                       "options" => " 110V ,220V,  "
                     }
                   }
                 }
               })

      assert [type] = Machines.list_machine_types()

      assert type.field_template == [
               %{
                 "key" => "power_kw",
                 "label" => "Power",
                 "type" => "number",
                 "unit" => "kW",
                 "required" => true,
                 "options" => []
               },
               %{
                 "key" => "voltage",
                 "label" => "Voltage",
                 "type" => "select",
                 "unit" => "",
                 "required" => false,
                 "options" => ["110V", "220V"]
               }
             ]
    end

    test "an unchecked required checkbox (submitted as \"false\") is stored as false", %{
      conn: conn
    } do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})

      assert {:error, {:live_redirect, _}} =
               render_submit(view, "save", %{
                 "machine_type" => %{
                   "name" => "CNC",
                   "field_template" => %{
                     "0" => %{
                       "key" => "power_kw",
                       "label" => "Power",
                       "type" => "number",
                       "unit" => "",
                       "required" => "false",
                       "options" => ""
                     }
                   }
                 }
               })

      assert [%{field_template: [%{"required" => false}]}] = Machines.list_machine_types()
    end

    test "an invalid row (select without options) fails validation, shows the error, and keeps the row",
         %{
           conn: conn
         } do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      render_click(view, "add_field_row", %{})

      html =
        render_submit(view, "save", %{
          "machine_type" => %{
            "name" => "CNC",
            "field_template" => %{
              "0" => %{
                "key" => "voltage",
                "label" => "Voltage",
                "type" => "select",
                "unit" => "",
                "required" => "false",
                "options" => ""
              }
            }
          }
        })

      assert html =~ "invalid row at index 0"
      assert Machines.list_machine_types() == []

      assert has_element?(
               view,
               "input[name='machine_type[field_template][0][key]'][value='voltage']"
             )
    end

    test "editing an existing type replaces its field_template (full replace, not append)", %{
      conn: conn
    } do
      {:ok, type} =
        Machines.create_machine_type(%{
          name: "CNC",
          field_template: [%{"key" => "old_field", "label" => "Old", "type" => "text"}]
        })

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, edit_path(type))

      assert {:error, {:live_redirect, _}} =
               render_submit(view, "save", %{
                 "machine_type" => %{
                   "name" => "CNC",
                   "field_template" => %{
                     "0" => %{
                       "key" => "new_field",
                       "label" => "New",
                       "type" => "text",
                       "unit" => "",
                       "required" => "false",
                       "options" => ""
                     }
                   }
                 }
               })

      updated = Machines.get_machine_type(type.uuid)
      assert [%{"key" => "new_field"}] = updated.field_template
    end
  end
end
