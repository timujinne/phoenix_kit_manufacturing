defmodule PhoenixKitManufacturing.Schemas.MachineTypeTest do
  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.Schemas.MachineType

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "is valid with just a name" do
      changeset = MachineType.changeset(%MachineType{}, %{name: "CNC"})
      assert changeset.valid?
    end

    test "requires a name" do
      changeset = MachineType.changeset(%MachineType{}, %{description: "no name"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "only allows active/inactive statuses" do
      assert MachineType.changeset(%MachineType{}, %{name: "X", status: "active"}).valid?
      assert MachineType.changeset(%MachineType{}, %{name: "X", status: "inactive"}).valid?
      refute MachineType.changeset(%MachineType{}, %{name: "X", status: "retired"}).valid?
    end

    test "caps the description length" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "X",
          description: String.duplicate("d", 1001)
        })

      refute changeset.valid?
      assert %{description: [_]} = errors_on(changeset)
    end

    test "defaults status to active on a new struct" do
      assert %MachineType{status: "active"} = %MachineType{}
    end
  end

  describe "changeset/2 field_template" do
    test "defaults to an empty list" do
      changeset = MachineType.changeset(%MachineType{}, %{name: "X"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :field_template) == []
    end

    test "accepts a valid template (text/number/date/boolean/select rows)" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [
            %{key: "power_kw", label: "Power (kW)", type: "number", unit: "kW", required: true},
            %{key: "install_date", label: "Install date", type: "date"},
            %{key: "has_coolant", label: "Has coolant", type: "boolean", required: false},
            %{
              key: "drive_type",
              label: "Drive type",
              type: "select",
              options: ["belt", "direct", "gearbox"]
            }
          ]
        })

      assert changeset.valid?
    end

    test "accepts string-keyed rows (as decoded from LiveView form params)" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          "name" => "CNC",
          "field_template" => [
            %{"key" => "power_kw", "label" => "Power (kW)", "type" => "number"}
          ]
        })

      assert changeset.valid?
    end

    test "select without options is invalid" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [%{key: "drive_type", label: "Drive type", type: "select"}]
        })

      refute changeset.valid?
      assert %{field_template: ["invalid row at index 0"]} = errors_on(changeset)
    end

    test "select with an empty options list is invalid" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [
            %{key: "drive_type", label: "Drive type", type: "select", options: []}
          ]
        })

      refute changeset.valid?
      assert %{field_template: ["invalid row at index 0"]} = errors_on(changeset)
    end

    test "unknown type is invalid" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [%{key: "foo", label: "Foo", type: "textarea"}]
        })

      refute changeset.valid?
      assert %{field_template: ["invalid row at index 0"]} = errors_on(changeset)
    end

    test "blank key or label is invalid" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [%{key: "", label: "Foo", type: "text"}]
        })

      refute changeset.valid?

      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [%{key: "foo", label: "  ", type: "text"}]
        })

      refute changeset.valid?
    end

    test "key must be lowercase alphanumerics/underscore only" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [%{key: "Power KW", label: "Power", type: "text"}]
        })

      refute changeset.valid?
      assert %{field_template: ["invalid row at index 0"]} = errors_on(changeset)
    end

    test "duplicate key within the same template is invalid" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [
            %{key: "power_kw", label: "Power", type: "number"},
            %{key: "power_kw", label: "Power again", type: "text"}
          ]
        })

      refute changeset.valid?
      assert %{field_template: ["duplicate key: power_kw"]} = errors_on(changeset)
    end

    test "a non-map row is invalid" do
      # A raw non-map array element fails Ecto's own `{:array, :map}` cast
      # before `validate_field_template/1` ever runs, so the changeset is
      # invalid with Ecto's generic cast error rather than the custom
      # "invalid row at index N" message (that message is only reachable
      # for elements that *are* maps but semantically malformed).
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: ["not a row"]
        })

      refute changeset.valid?
      assert %{field_template: [_reason]} = errors_on(changeset)
    end

    test "reports each malformed row by its own index" do
      changeset =
        MachineType.changeset(%MachineType{}, %{
          name: "CNC",
          field_template: [
            %{key: "ok", label: "Ok", type: "text"},
            %{key: "bad", label: "Bad", type: "unknown"}
          ]
        })

      refute changeset.valid?
      assert %{field_template: ["invalid row at index 1"]} = errors_on(changeset)
    end
  end
end
