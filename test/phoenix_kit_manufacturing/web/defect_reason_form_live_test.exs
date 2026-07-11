defmodule PhoenixKitManufacturing.Web.DefectReasonFormLiveTest do
  # Integration tests — require PostgreSQL, excluded when the DB is
  # unavailable (see test_helper.exs).
  use PhoenixKitManufacturing.LiveCase

  alias PhoenixKitManufacturing.DefectReasons

  defp new_path, do: "/en/admin/manufacturing/machines/defect-reasons/new"

  defp edit_path(defect_reason),
    do: "/en/admin/manufacturing/machines/defect-reasons/#{defect_reason.uuid}/edit"

  describe "mount" do
    test "renders the new-defect-reason form with name/description/status fields", %{
      conn: conn
    } do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, new_path())

      assert html =~ "New Defect Reason"
      assert html =~ "defect_reason[name]"
      assert html =~ "defect_reason[description]"
      assert html =~ "Active"
      assert html =~ "Inactive"
    end

    test "renders the edit form pre-filled from the existing defect reason", %{conn: conn} do
      {:ok, defect_reason} =
        DefectReasons.create_defect_reason(%{
          name: "Scratched surface",
          description: "Visible scratch on the finished part"
        })

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, edit_path(defect_reason))

      assert html =~ "Edit Scratched surface"
      assert html =~ "Scratched surface"
      assert html =~ "Visible scratch on the finished part"
    end

    test "redirects to the defect reasons list with a flash when the uuid doesn't exist", %{
      conn: conn
    } do
      conn = put_test_scope(conn, fake_scope())

      assert {:error, {:live_redirect, %{to: to} = redirect_opts}} =
               live(conn, edit_path(%{uuid: Ecto.UUID.generate()}))

      assert to =~ "manufacturing/machines/defect-reasons"

      if flash = redirect_opts[:flash] do
        assert Phoenix.Flash.get(flash, :error) =~ "Defect reason not found"
      end
    end
  end

  describe "save" do
    test "creates a defect reason with name/description/status", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("form",
                 defect_reason: %{
                   name: "Scratched surface",
                   description: "Visible scratch on the finished part",
                   status: "active"
                 }
               )
               |> render_submit()

      assert to =~ "manufacturing/machines/defect-reasons"

      assert [defect_reason] = DefectReasons.list_defect_reasons()
      assert defect_reason.name == "Scratched surface"
      assert defect_reason.description == "Visible scratch on the finished part"
      assert defect_reason.status == "active"
    end

    test "updates an existing defect reason in place (no new row created)", %{conn: conn} do
      {:ok, defect_reason} = DefectReasons.create_defect_reason(%{name: "Scratched surface"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, edit_path(defect_reason))

      assert {:error, {:live_redirect, _}} =
               view
               |> form("form",
                 defect_reason: %{
                   name: "Scratched surface",
                   description: "Updated description",
                   status: "inactive"
                 }
               )
               |> render_submit()

      assert DefectReasons.count_defect_reasons() == 1
      updated = DefectReasons.get_defect_reason(defect_reason.uuid)
      assert updated.description == "Updated description"
      assert updated.status == "inactive"
    end

    test "a blank name fails validation, shows the error, and does not create a row", %{
      conn: conn
    } do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      html =
        view
        |> form("form", defect_reason: %{name: "", description: "Some description"})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      assert DefectReasons.list_defect_reasons() == []
    end

    test "records the actor uuid on the activity log when creating", %{conn: conn} do
      scope = fake_scope()
      conn = put_test_scope(conn, scope)
      {:ok, view, _html} = live(conn, new_path())

      assert {:error, {:live_redirect, _}} =
               view
               |> form("form", defect_reason: %{name: "Scratched surface"})
               |> render_submit()

      assert [defect_reason] = DefectReasons.list_defect_reasons()

      assert_activity_logged("defect_reason.created",
        actor_uuid: scope.user.uuid,
        resource_uuid: defect_reason.uuid
      )
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated messages instead of crashing", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, new_path())

      send(view.pid, :some_unrelated_message)
      assert render(view) =~ "New Defect Reason"
    end
  end
end
