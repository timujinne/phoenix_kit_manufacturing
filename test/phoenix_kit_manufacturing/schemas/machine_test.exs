defmodule PhoenixKitManufacturing.Schemas.MachineTest do
  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.Schemas.Machine

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "is valid with just a name" do
      changeset = Machine.changeset(%Machine{}, %{name: "CNC-01"})
      assert changeset.valid?
    end

    test "casts the full set of optional fields" do
      attrs = %{
        name: "CNC-01",
        code: "M-001",
        manufacturer: "Haas",
        serial_number: "SN-123",
        description: "3-axis mill",
        location_note: "Shop floor A",
        status: "maintenance",
        metadata: %{"power_kw" => 7.5}
      }

      changeset = Machine.changeset(%Machine{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == "maintenance"
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{"power_kw" => 7.5}
    end

    test "requires a name" do
      changeset = Machine.changeset(%Machine{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an unknown status" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", status: "on_fire"})
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts each documented status" do
      for status <- Machine.statuses() do
        changeset = Machine.changeset(%Machine{}, %{name: "X", status: status})
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "enforces the name length ceiling" do
      changeset = Machine.changeset(%Machine{}, %{name: String.duplicate("a", 256)})
      refute changeset.valid?
      assert %{name: [_]} = errors_on(changeset)
    end

    test "defaults status to active on a new struct" do
      assert %Machine{status: "active"} = %Machine{}
    end
  end

  describe "changeset/2 - V2 passport fields" do
    test "casts the full set of V2 optional fields" do
      attrs = %{
        name: "CNC-02",
        model: "VF-2",
        manufacture_year: 2020,
        commissioned_on: ~D[2020-03-01],
        warranty_until: ~D[2022-03-01],
        to_last_on: ~D[2026-01-01],
        to_interval_days: 90,
        to_next_on: ~D[2026-04-01],
        notes: "Runs the third shift",
        location_uuid: Ecto.UUID.generate(),
        space_uuid: Ecto.UUID.generate()
      }

      changeset = Machine.changeset(%Machine{}, attrs)
      assert changeset.valid?
    end

    test "accepts the repair and mothballed statuses" do
      assert Machine.changeset(%Machine{}, %{name: "X", status: "repair"}).valid?
      assert Machine.changeset(%Machine{}, %{name: "X", status: "mothballed"}).valid?
    end

    test "still rejects an unknown status alongside the wider V2 list" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", status: "on_fire"})
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "enforces the model length ceiling" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", model: String.duplicate("m", 256)})
      refute changeset.valid?
      assert %{model: [_]} = errors_on(changeset)
    end

    test "enforces the notes length ceiling" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", notes: String.duplicate("n", 2001)})
      refute changeset.valid?
      assert %{notes: [_]} = errors_on(changeset)
    end

    test "rejects a zero or negative to_interval_days" do
      refute Machine.changeset(%Machine{}, %{name: "X", to_interval_days: 0}).valid?
      refute Machine.changeset(%Machine{}, %{name: "X", to_interval_days: -5}).valid?
    end

    test "accepts a positive to_interval_days" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", to_interval_days: 30})
      assert changeset.valid?
    end

    test "leaves to_interval_days unvalidated when absent" do
      assert Machine.changeset(%Machine{}, %{name: "X"}).valid?
    end
  end

  describe "changeset/2 - auto-computed to_next_on" do
    test "computes to_next_on from to_last_on + to_interval_days when not given" do
      changeset =
        Machine.changeset(%Machine{}, %{
          name: "X",
          to_last_on: ~D[2026-01-01],
          to_interval_days: 30
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :to_next_on) == ~D[2026-01-31]
    end

    test "does not overwrite an explicitly given to_next_on" do
      changeset =
        Machine.changeset(%Machine{}, %{
          name: "X",
          to_last_on: ~D[2026-01-01],
          to_interval_days: 30,
          to_next_on: ~D[2026-06-15]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :to_next_on) == ~D[2026-06-15]
    end

    test "leaves to_next_on untouched when to_last_on is missing" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", to_interval_days: 30})
      refute Ecto.Changeset.get_change(changeset, :to_next_on)
    end

    test "leaves to_next_on untouched when to_interval_days is missing" do
      changeset = Machine.changeset(%Machine{}, %{name: "X", to_last_on: ~D[2026-01-01]})
      refute Ecto.Changeset.get_change(changeset, :to_next_on)
    end

    test "recomputes from stored to_last_on/to_interval_days when editing an unrelated field" do
      # Documents the auto-recompute contract: to_next_on tracks
      # to_last_on/to_interval_days on every save unless *this* save
      # explicitly submits its own to_next_on.
      machine = %Machine{
        name: "X",
        to_last_on: ~D[2026-01-01],
        to_interval_days: 30,
        to_next_on: ~D[2026-09-01]
      }

      changeset = Machine.changeset(machine, %{code: "NEW-CODE"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :to_next_on) == ~D[2026-01-31]
    end
  end
end
