defmodule PhoenixKitManufacturing.Operations do
  @moduledoc """
  Context module for the global operations directory (e.g. "Cutting",
  "Welding", "Assembly").

  Mirrors the CRUD shape of the "Machine Types" section in
  `PhoenixKitManufacturing.Machines` — operations are hard-deleted,
  standalone reference data. Deleting an operation cascades to its
  `phoenix_kit_machine_operations` links at the database level (`ON DELETE
  CASCADE`); linked machines are unaffected, they just lose the link. The
  machine-side of that join (listing a machine's linked operations, syncing
  the link set, per-machine norm overrides) lives in
  `PhoenixKitManufacturing.Machines`'s "Machine ↔ Operation linking"
  section, not here — this module only owns the operations directory
  itself.

  ## Activity logging

  Every mutating function accepts `opts \\ []`. When `actor_uuid:` is
  present in opts, the mutation is logged via `PhoenixKit.Activity.log/1`
  under the `"manufacturing"` module key, resource type `"operation"`.
  Logging is fire-and-forget — both `PhoenixKit.Activity.log/1` and this
  module's `maybe_log_activity/4` rescue internally, so a host that hasn't
  run core's activity migration still completes the primary write; the
  logging failure only degrades to a `Logger.warning`. These are private
  copies of the same helpers `Machines` defines — standalone contexts don't
  share a mixin (see `dev_docs/IMPLEMENTATION_PLAN.md` §3).

  ## Usage from IEx

      alias PhoenixKitManufacturing.Operations

      {:ok, cutting} = Operations.create_operation(%{name: "Cutting", unit: "pcs"})
      Operations.list_operations(status: "active")
      Operations.count_operations()
  """

  import Ecto.Query, warn: false

  require Logger

  alias PhoenixKitManufacturing.Schemas.Operation

  @module_key "manufacturing"
  @resource_type "operation"

  @type opts :: keyword()
  @type status_filter :: [status: String.t()]

  defp repo, do: PhoenixKit.RepoHelper.repo()

  @doc """
  Lists all operations, ordered by name.

  ## Options

    * `:status` — filter by status (e.g. `"active"`, `"inactive"`).
  """
  @spec list_operations(status_filter) :: [Operation.t()]
  def list_operations(opts \\ []) do
    Operation
    |> from(order_by: [asc: :name])
    |> filter_status(opts)
    |> repo().all()
  end

  @doc "Fetches an operation by UUID. Returns `nil` if not found."
  @spec get_operation(String.t()) :: Operation.t() | nil
  def get_operation(uuid), do: repo().get(Operation, uuid)

  @doc "Fetches an operation by name (case-sensitive). Returns `nil` if not found."
  @spec get_operation_by_name(String.t()) :: Operation.t() | nil
  def get_operation_by_name(name), do: repo().get_by(Operation, name: name)

  @doc "Returns the total count of operations."
  @spec count_operations(status_filter) :: non_neg_integer()
  def count_operations(opts \\ []) do
    Operation
    |> from(select: count())
    |> filter_status(opts)
    |> repo().one()
  end

  @doc "Creates an operation. Required: `:name`. Optional: `:unit`, `:base_time_norm_seconds`, `:status`, `:data`."
  @spec create_operation(map(), opts) :: {:ok, Operation.t()} | {:error, Ecto.Changeset.t()}
  def create_operation(attrs, opts \\ []) do
    %Operation{}
    |> Operation.changeset(attrs)
    |> repo().insert()
    |> log_activity("operation.created", opts)
  end

  @doc "Updates an operation with the given attributes."
  @spec update_operation(Operation.t(), map(), opts) ::
          {:ok, Operation.t()} | {:error, Ecto.Changeset.t()}
  def update_operation(%Operation{} = operation, attrs, opts \\ []) do
    operation
    |> Operation.changeset(attrs)
    |> repo().update()
    |> log_activity("operation.updated", opts)
  end

  @doc "Hard-deletes an operation. Cascades to machine ↔ operation links (machines keep existing, lose the link)."
  @spec delete_operation(Operation.t(), opts) ::
          {:ok, Operation.t()} | {:error, Ecto.Changeset.t()}
  def delete_operation(%Operation{} = operation, opts \\ []) do
    operation
    |> repo().delete()
    |> log_activity("operation.deleted", opts)
  end

  @doc "Returns an `Ecto.Changeset` for tracking operation changes."
  @spec change_operation(Operation.t(), map()) :: Ecto.Changeset.t()
  def change_operation(%Operation{} = operation, attrs \\ %{}) do
    Operation.changeset(operation, attrs)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Query helpers
  # ═══════════════════════════════════════════════════════════════════

  defp filter_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [x], x.status == ^status)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Activity logging helpers (private copy of Machines' pattern — see
  # moduledoc for why standalone contexts don't share a mixin)
  # ═══════════════════════════════════════════════════════════════════

  # Pipe-step: logs on {:ok, struct} with full metadata; on
  # {:error, changeset} logs a `db_pending: true` audit row so the
  # user-initiated action survives even when the primary write fails.
  # Passes the original tuple through unchanged.
  defp log_activity({:ok, %Operation{} = operation} = ok, action, opts) do
    maybe_log_activity(action, operation.uuid, opts, operation_metadata(operation))
    ok
  end

  defp log_activity({:error, %Ecto.Changeset{} = changeset} = err, action, opts) do
    maybe_log_activity(
      action,
      Map.get(changeset.data, :uuid),
      opts,
      changeset_error_metadata(changeset)
    )

    err
  end

  defp log_activity({:error, _} = err, _action, _opts), do: err

  # Low-level: fire-and-forget log, guarded so it never crashes callers.
  defp maybe_log_activity(action, resource_uuid, opts, metadata) do
    if Code.ensure_loaded?(PhoenixKit.Activity) do
      PhoenixKit.Activity.log(%{
        action: action,
        module: @module_key,
        mode: Keyword.get(opts, :mode, "manual"),
        actor_uuid: Keyword.get(opts, :actor_uuid),
        resource_type: @resource_type,
        resource_uuid: resource_uuid,
        metadata: metadata
      })
    end

    :ok
  rescue
    e in Postgrex.Error ->
      # Host hasn't run core's activity migration — swallow silently.
      if match?(%{postgres: %{code: :undefined_table}}, e) do
        :ok
      else
        Logger.warning("[Manufacturing] Activity log failed: #{Exception.message(e)}")
        :ok
      end

    e ->
      Logger.warning("[Manufacturing] Activity log error: #{Exception.message(e)}")
      :ok
  end

  # PII-safe changeset metadata: invalid field names + a db_pending marker.
  # Never includes the rejected values themselves.
  defp changeset_error_metadata(%Ecto.Changeset{errors: errors}) do
    %{
      "db_pending" => true,
      "error_fields" => errors |> Enum.map(fn {field, _} -> to_string(field) end) |> Enum.uniq()
    }
  end

  defp operation_metadata(%Operation{} = o) do
    %{"name" => o.name, "status" => o.status}
  end
end
