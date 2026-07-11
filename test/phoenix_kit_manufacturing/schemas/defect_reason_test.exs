defmodule PhoenixKitManufacturing.Schemas.DefectReasonTest do
  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.Schemas.DefectReason

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "is valid with just a name" do
      changeset = DefectReason.changeset(%DefectReason{}, %{name: "Scratched surface"})
      assert changeset.valid?
    end

    test "requires a name" do
      changeset = DefectReason.changeset(%DefectReason{}, %{description: "no name"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "only allows active/inactive statuses" do
      assert DefectReason.changeset(%DefectReason{}, %{name: "X", status: "active"}).valid?
      assert DefectReason.changeset(%DefectReason{}, %{name: "X", status: "inactive"}).valid?
      refute DefectReason.changeset(%DefectReason{}, %{name: "X", status: "retired"}).valid?
    end

    test "caps the name length" do
      changeset = DefectReason.changeset(%DefectReason{}, %{name: String.duplicate("n", 256)})
      refute changeset.valid?
      assert %{name: [_]} = errors_on(changeset)
    end

    test "caps the description length" do
      changeset =
        DefectReason.changeset(%DefectReason{}, %{
          name: "X",
          description: String.duplicate("d", 1001)
        })

      refute changeset.valid?
      assert %{description: [_]} = errors_on(changeset)
    end

    test "defaults status to active on a new struct" do
      assert %DefectReason{status: "active"} = %DefectReason{}
    end

    test "casts the full set of optional fields" do
      attrs = %{
        name: "Wrong dimensions",
        description: "Part measured out of tolerance",
        status: "inactive",
        data: %{"i18n" => %{"en" => %{"name" => "Wrong dimensions"}}}
      }

      changeset = DefectReason.changeset(%DefectReason{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :description) == attrs.description
      assert Ecto.Changeset.get_change(changeset, :status) == "inactive"
    end

    test "statuses/0 returns the valid status list" do
      assert DefectReason.statuses() == ~w(active inactive)
    end
  end
end
