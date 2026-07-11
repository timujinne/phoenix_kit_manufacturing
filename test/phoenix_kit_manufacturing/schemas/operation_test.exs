defmodule PhoenixKitManufacturing.Schemas.OperationTest do
  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.Schemas.Operation

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "is valid with just a name" do
      changeset = Operation.changeset(%Operation{}, %{name: "Cutting"})
      assert changeset.valid?
    end

    test "requires a name" do
      changeset = Operation.changeset(%Operation{}, %{unit: "pcs"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts the full set of optional fields" do
      attrs = %{
        name: "Welding",
        unit: "pcs",
        base_time_norm_seconds: 120,
        status: "inactive",
        data: %{"i18n" => %{"en" => %{"name" => "Welding"}}}
      }

      changeset = Operation.changeset(%Operation{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :unit) == "pcs"
      assert Ecto.Changeset.get_change(changeset, :base_time_norm_seconds) == 120
      assert Ecto.Changeset.get_change(changeset, :status) == "inactive"
    end

    test "only allows active/inactive statuses" do
      for status <- Operation.statuses() do
        changeset = Operation.changeset(%Operation{}, %{name: "X", status: status})
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "rejects an unknown status" do
      changeset = Operation.changeset(%Operation{}, %{name: "X", status: "archived"})
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "defaults status to active on a new struct" do
      assert %Operation{status: "active"} = %Operation{}
    end

    test "enforces the name length ceiling" do
      changeset = Operation.changeset(%Operation{}, %{name: String.duplicate("a", 256)})
      refute changeset.valid?
      assert %{name: [_]} = errors_on(changeset)
    end

    test "enforces the unit length ceiling" do
      changeset =
        Operation.changeset(%Operation{}, %{name: "X", unit: String.duplicate("u", 51)})

      refute changeset.valid?
      assert %{unit: [_]} = errors_on(changeset)
    end

    test "rejects a negative base_time_norm_seconds" do
      changeset = Operation.changeset(%Operation{}, %{name: "X", base_time_norm_seconds: -1})
      refute changeset.valid?
      assert %{base_time_norm_seconds: [_]} = errors_on(changeset)
    end

    test "accepts a zero base_time_norm_seconds" do
      changeset = Operation.changeset(%Operation{}, %{name: "X", base_time_norm_seconds: 0})
      assert changeset.valid?
    end

    test "leaves base_time_norm_seconds unvalidated when absent" do
      assert Operation.changeset(%Operation{}, %{name: "X"}).valid?
    end
  end
end
