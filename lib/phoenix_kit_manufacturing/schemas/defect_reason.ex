defmodule PhoenixKitManufacturing.Schemas.DefectReason do
  @moduledoc """
  Schema for the global defect-reasons directory (e.g., "Scratched
  surface", "Wrong dimensions", "Missing part").

  A plain reference book — `name` and `description` are translatable via
  core `MultilangForm` (stored in the `data` JSONB column, mirroring
  `MachineType`); `status` is a plain, non-translatable column. This wave
  does not link defect reasons to machines, operations, or any other
  resource — no M2M association here, only the directory itself (see §Б.4
  of the development plan).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @statuses ~w(active inactive)

  schema "phoenix_kit_defect_reasons" do
    field(:name, :string)
    field(:description, :string)
    field(:status, :string, default: "active")

    # Multilang translations (name/description), managed by MultilangForm.
    field(:data, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [:description, :status, :data]

  @doc "Builds a changeset for a defect reason."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(defect_reason, attrs) do
    defect_reason
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:status, @statuses)
  end

  @doc "The list of valid status values."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end
