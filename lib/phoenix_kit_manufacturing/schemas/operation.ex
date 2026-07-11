defmodule PhoenixKitManufacturing.Schemas.Operation do
  @moduledoc """
  Schema for the global operations directory (e.g., "Cutting", "Welding",
  "Assembly").

  An operation carries an optional unit of measure and a base time norm
  (`base_time_norm_seconds`) that machines linked to it inherit by default.
  A machine's link to an operation — `MachineOperation` — may override that
  base norm per machine (`nil` override falls back to the operation's own
  value); see `PhoenixKitManufacturing.Machines.list_machine_operations/1`.

  `name` is translatable via core `MultilangForm` (stored in the `data`
  JSONB column, mirroring `MachineType`); `unit`, `base_time_norm_seconds`,
  and `status` are plain, non-translatable columns.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @statuses ~w(active inactive)

  schema "phoenix_kit_operations" do
    field(:name, :string)
    field(:unit, :string)
    field(:base_time_norm_seconds, :integer)
    field(:status, :string, default: "active")

    # Multilang translation for `name`, managed by MultilangForm.
    field(:data, :map, default: %{})

    has_many(:machine_operations, PhoenixKitManufacturing.Schemas.MachineOperation,
      foreign_key: :operation_uuid,
      references: :uuid
    )

    has_many(:machines, through: [:machine_operations, :machine])

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [:unit, :base_time_norm_seconds, :status, :data]

  @doc "Builds a changeset for an operation."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(operation, attrs) do
    operation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:unit, max: 50)
    |> validate_number(:base_time_norm_seconds, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, @statuses)
  end

  @doc "The list of valid status values."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end
