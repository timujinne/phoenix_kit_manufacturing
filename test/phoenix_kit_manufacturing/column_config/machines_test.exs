defmodule PhoenixKitManufacturing.ColumnConfig.MachinesTest do
  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.ColumnConfig.Machines, as: C
  alias PhoenixKitManufacturing.Schemas.Machine

  defp entry(overrides) do
    Map.merge(
      %{
        uuid: "u",
        name: "CNC Mill",
        code: "CNC-01",
        status: "active",
        status_label: "Active",
        location: "Building A / Room 3",
        manufacturer: "Haas",
        model: "VF-2",
        manufacture_year: 2018,
        commissioned_on: ~D[2018-05-01],
        warranty_until: ~D[2020-05-01],
        to_next_on: ~D[2026-08-01]
      },
      overrides
    )
  end

  test "scope/0 is manufacturing_machines" do
    assert C.scope() == "manufacturing_machines"
  end

  test "default_columns/0 are the starred set in order" do
    assert C.default_columns() == ["name", "code", "status", "location"]
  end

  test "all_column_ids/0 covers every column (types deferred to M17)" do
    assert C.all_column_ids() == [
             "name",
             "code",
             "status",
             "location",
             "manufacturer",
             "model",
             "manufacture_year",
             "commissioned_on",
             "warranty_until",
             "to_next_on"
           ]

    refute "types" in C.all_column_ids()
  end

  test "validate_columns/1 drops unknown ids, keeps order" do
    assert C.validate_columns(["code", "bogus", "name"]) == ["code", "name"]
  end

  test "validate_filters/1 keeps only filterable ids" do
    assert C.validate_filters(["status", "nope"]) == ["status"]
  end

  test "text filter on name matches case-insensitively" do
    meta = C.column_metadata_map()["name"]
    rows = [entry(%{name: "CNC Mill"}), entry(%{name: "Laser Cutter"})]
    assert [%{name: "CNC Mill"}] = meta.filter_apply.(rows, "cnc")
    assert rows == meta.filter_apply.(rows, "")
  end

  test "enum filter on status matches exactly; options cover every Machine status" do
    meta = C.column_metadata_map()["status"]
    rows = [entry(%{status: "active"}), entry(%{status: "repair"})]
    assert [%{status: "repair"}] = meta.filter_apply.(rows, "repair")

    assert meta.filter_options.(rows) == [
             {"active", "Active"},
             {"maintenance", "Maintenance"},
             {"repair", "Repair"},
             {"mothballed", "Mothballed"},
             {"decommissioned", "Decommissioned"}
           ]

    assert Enum.map(meta.filter_options.(rows), &elem(&1, 0)) == Machine.statuses()
  end

  test "numeric_range filter on manufacture_year keeps rows within [min, max]" do
    meta = C.column_metadata_map()["manufacture_year"]

    rows = [
      entry(%{manufacture_year: 2005}),
      entry(%{manufacture_year: 2015}),
      entry(%{manufacture_year: 2023})
    ]

    assert [%{manufacture_year: 2015}] =
             meta.filter_apply.(rows, %{"min" => "2010", "max" => "2020"})

    assert rows == meta.filter_apply.(rows, %{"min" => "", "max" => ""})
  end

  test "date_range filter on commissioned_on keeps rows within [from, to]" do
    meta = C.column_metadata_map()["commissioned_on"]

    rows = [
      entry(%{commissioned_on: ~D[2015-01-01]}),
      entry(%{commissioned_on: ~D[2019-06-01]}),
      entry(%{commissioned_on: nil})
    ]

    kept = meta.filter_apply.(rows, %{"from" => "2018-01-01", "to" => "2020-01-01"})
    assert [%{commissioned_on: ~D[2019-06-01]}] = kept
  end

  test "sort_key for name orders ascending case-insensitively" do
    meta = C.column_metadata_map()["name"]

    rows = [entry(%{name: "Zebra Cutter"}), entry(%{name: "apple Press"})]

    # A raw (non-downcased) string sort_key would put "Zebra Cutter" first —
    # in ASCII, every uppercase letter sorts below every lowercase one, so
    # "Z" (90) < "a" (97) even though "zebra" alphabetically comes after
    # "apple". The case-insensitive sort_key must correct for that.
    assert Enum.sort_by(rows, meta.sort_key, :asc) ==
             [entry(%{name: "apple Press"}), entry(%{name: "Zebra Cutter"})]
  end

  test "sort_key for to_next_on orders chronologically and puts nil first ascending" do
    meta = C.column_metadata_map()["to_next_on"]

    rows = [
      entry(%{to_next_on: ~D[2026-12-01]}),
      entry(%{to_next_on: nil}),
      entry(%{to_next_on: ~D[2026-08-01]})
    ]

    assert Enum.sort_by(rows, meta.sort_key, :asc) == [
             entry(%{to_next_on: nil}),
             entry(%{to_next_on: ~D[2026-08-01]}),
             entry(%{to_next_on: ~D[2026-12-01]})
           ]
  end

  test "every column has the mandatory structural fields (align, sort_key, default_dir, filter_type, filter_apply)" do
    for meta <- C.available_columns() do
      assert is_binary(meta.id)
      assert is_function(meta.label, 0)
      assert is_boolean(meta.default?)
      assert meta.align in [:left, :right]
      assert is_boolean(meta.sortable?)
      assert is_boolean(meta.filterable?)

      if meta.sortable? do
        assert is_function(meta.sort_key, 1)
        assert meta.default_dir in [:asc, :desc]
      end

      if meta.filterable? do
        assert meta.filter_type in [:text, :enum, :date_range, :numeric_range]
        assert is_function(meta.filter_apply, 2)
      end

      if meta.filter_type == :enum do
        assert is_function(meta.filter_options, 1)
      end
    end
  end
end
