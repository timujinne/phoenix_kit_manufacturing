defmodule PhoenixKitManufacturing.Schemas.MachineOperation do
  @moduledoc """
  Join table for the many-to-many between machines and operations.

  Carries an optional per-machine `time_norm_seconds` override — `nil`
  means "use the linked operation's `base_time_norm_seconds`"; see
  `PhoenixKitManufacturing.Machines.list_machine_operations/1`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "phoenix_kit_machine_operations" do
    belongs_to(:machine, PhoenixKitManufacturing.Schemas.Machine,
      foreign_key: :machine_uuid,
      references: :uuid,
      type: UUIDv7
    )

    belongs_to(:operation, PhoenixKitManufacturing.Schemas.Operation,
      foreign_key: :operation_uuid,
      references: :uuid,
      type: UUIDv7
    )

    # Optional per-machine override of the linked operation's
    # base_time_norm_seconds. nil ⇒ use the operation's base norm.
    field(:time_norm_seconds, :integer)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an insert changeset for a machine ↔ operation link.

  Casts the two FK columns, the optional `time_norm_seconds` override, and
  timestamps; wires `assoc_constraint/2` on both associations so an FK
  violation comes back as a clean `{:error, changeset}` instead of raising
  `Ecto.ConstraintError`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(machine_operation, attrs) do
    machine_operation
    |> cast(attrs, [:machine_uuid, :operation_uuid, :time_norm_seconds, :inserted_at, :updated_at])
    |> validate_required([:machine_uuid, :operation_uuid])
    |> validate_number(:time_norm_seconds, greater_than_or_equal_to: 0)
    |> assoc_constraint(:machine)
    |> assoc_constraint(:operation)
  end
end
