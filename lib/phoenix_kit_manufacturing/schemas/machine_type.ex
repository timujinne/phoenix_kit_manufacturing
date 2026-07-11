defmodule PhoenixKitManufacturing.Schemas.MachineType do
  @moduledoc """
  Schema for machine types (e.g., CNC, Milling, Press, Laser cutter).

  `field_template` defines the dynamic `metadata` fields rendered on the
  machine form for machines linked to this type (power rating, working
  area, …). Each entry is a map with a `key`, a `label`, a `type`
  (`text`/`number`/`date`/`boolean`/`select`), an optional `unit`, an
  optional `required` flag, and — mandatory and non-empty only when
  `type == "select"` — an `options` list. See `validate_field_template/1`
  for the full per-row contract. When several linked types define the same
  `key`, merging them is the caller's job, not this schema's — see
  `PhoenixKitManufacturing.Machines.merged_field_template/1`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @statuses ~w(active inactive)

  @field_template_types ~w(text number date boolean select)
  @field_template_key_format ~r/^[a-z0-9_]+$/

  schema "phoenix_kit_machine_types" do
    field(:name, :string)
    field(:description, :string)
    field(:status, :string, default: "active")

    # Multilang translations (name/description), managed by MultilangForm.
    field(:data, :map, default: %{})

    # Dynamic metadata field definitions rendered on the machine form for
    # machines linked to this type. See `validate_field_template/1`.
    field(:field_template, {:array, :map}, default: [])

    has_many(:machine_type_assignments, PhoenixKitManufacturing.Schemas.MachineTypeAssignment,
      foreign_key: :machine_type_uuid,
      references: :uuid
    )

    has_many(:machines, through: [:machine_type_assignments, :machine])

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [:description, :status, :data, :field_template]

  @doc "Builds a changeset for a machine type."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(machine_type, attrs) do
    machine_type
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:status, @statuses)
    |> validate_field_template()
  end

  @doc "The list of valid status values."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  # Validates every row of `field_template`. A row is a map with:
  #
  #   * `key` — non-blank string, `~r/^[a-z0-9_]+$/` (lowercase
  #     alphanumerics/underscore only — used as the `machine.metadata`
  #     JSON key and as an HTML form field name).
  #   * `label` — non-blank string.
  #   * `type` — one of `text`/`number`/`date`/`boolean`/`select`.
  #   * `unit` — optional string.
  #   * `required` — optional boolean.
  #   * `options` — list of non-blank strings; mandatory and non-empty when
  #     `type == "select"` (a select with no choices is meaningless),
  #     optional otherwise.
  #
  # A row failing any of the above adds a single
  # `"invalid row at index N"` error rather than one error per malformed
  # attribute — the row as a whole is malformed. A `key` repeated across
  # rows of the *same* template adds a `"duplicate key: ..."` error (a
  # machine can link several types; cross-type key collisions are resolved
  # by the merge step, not rejected here).
  @spec validate_field_template(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_field_template(changeset) do
    rows = get_field(changeset, :field_template) || []

    {changeset, _seen_keys} =
      rows
      |> Enum.with_index()
      |> Enum.reduce({changeset, MapSet.new()}, &validate_field_template_row/2)

    changeset
  end

  defp validate_field_template_row({row, index}, {changeset, seen_keys}) do
    cond do
      not valid_field_template_row?(row) ->
        {add_error(changeset, :field_template, "invalid row at index #{index}"), seen_keys}

      MapSet.member?(seen_keys, fetch_row(row, :key)) ->
        message = "duplicate key: #{fetch_row(row, :key)}"
        {add_error(changeset, :field_template, message), seen_keys}

      true ->
        {changeset, MapSet.put(seen_keys, fetch_row(row, :key))}
    end
  end

  defp valid_field_template_row?(row) when is_map(row) do
    key = fetch_row(row, :key)
    label = fetch_row(row, :label)
    type = fetch_row(row, :type)

    non_blank_string?(key) and String.match?(key, @field_template_key_format) and
      non_blank_string?(label) and
      type in @field_template_types and
      valid_field_template_unit?(fetch_row(row, :unit)) and
      valid_field_template_required?(fetch_row(row, :required)) and
      valid_field_template_options?(type, fetch_row(row, :options))
  end

  defp valid_field_template_row?(_row), do: false

  defp valid_field_template_unit?(nil), do: true
  defp valid_field_template_unit?(value), do: is_binary(value)

  defp valid_field_template_required?(nil), do: true
  defp valid_field_template_required?(value), do: is_boolean(value)

  # `select` needs at least one choice or it's meaningless; every other
  # type treats `options` as optional freeform metadata.
  defp valid_field_template_options?("select", options) do
    is_list(options) and options != [] and Enum.all?(options, &non_blank_string?/1)
  end

  defp valid_field_template_options?(_type, nil), do: true

  defp valid_field_template_options?(_type, options) do
    is_list(options) and Enum.all?(options, &non_blank_string?/1)
  end

  defp non_blank_string?(value), do: is_binary(value) and String.trim(value) != ""

  # Reads `atom_key` off a `field_template` row, trying the atom key first
  # and falling back to its string form: rows may be atom-keyed (built by
  # hand in Elixir/tests) or string-keyed (decoded from LiveView form
  # params). Uses `Map.has_key?/2` rather than a plain `||` fallback so a
  # present-but-falsy value (e.g. `required: false`) isn't mistaken for an
  # absent key.
  @spec fetch_row(map(), atom()) :: term()
  defp fetch_row(row, atom_key) when is_map(row) do
    string_key = Atom.to_string(atom_key)

    cond do
      Map.has_key?(row, atom_key) -> Map.get(row, atom_key)
      Map.has_key?(row, string_key) -> Map.get(row, string_key)
      true -> nil
    end
  end

  defp fetch_row(_row, _atom_key), do: nil
end
