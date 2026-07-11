defmodule PhoenixKitManufacturing.DefectReasons do
  @moduledoc """
  Context module for the global defect-reasons directory (e.g. "Scratched
  surface", "Wrong dimensions", "Missing part").

  Mirrors the CRUD shape of the "Machine Types" section in
  `PhoenixKitManufacturing.Machines` — defect reasons are hard-deleted,
  standalone reference data. This wave does not link defect reasons to
  machines, operations, or any other resource (see
  `Schemas.DefectReason`'s moduledoc) — no M2M linking section here, only
  the directory itself.

  ## Activity logging

  Every mutating function accepts `opts \\ []`. When `actor_uuid:` is
  present in opts, the mutation is logged via `PhoenixKit.Activity.log/1`
  under the `"manufacturing"` module key, resource type `"defect_reason"`.
  Logging is fire-and-forget — both `PhoenixKit.Activity.log/1` and this
  module's `maybe_log_activity/4` rescue internally, so a host that hasn't
  run core's activity migration still completes the primary write; the
  logging failure only degrades to a `Logger.warning`. These are private
  copies of the same helpers `Machines`/`Operations` define — standalone
  contexts don't share a mixin (see `dev_docs/IMPLEMENTATION_PLAN.md` §3).

  ## Usage from IEx

      alias PhoenixKitManufacturing.DefectReasons

      {:ok, scratch} = DefectReasons.create_defect_reason(%{name: "Scratched surface"})
      DefectReasons.list_defect_reasons(status: "active")
      DefectReasons.count_defect_reasons()
  """

  import Ecto.Query, warn: false

  require Logger

  alias PhoenixKitManufacturing.Schemas.DefectReason

  @module_key "manufacturing"
  @resource_type "defect_reason"

  @type opts :: keyword()
  @type status_filter :: [status: String.t()]

  defp repo, do: PhoenixKit.RepoHelper.repo()

  @doc """
  Lists all defect reasons, ordered by name.

  ## Options

    * `:status` — filter by status (e.g. `"active"`, `"inactive"`).
  """
  @spec list_defect_reasons(status_filter) :: [DefectReason.t()]
  def list_defect_reasons(opts \\ []) do
    DefectReason
    |> from(order_by: [asc: :name])
    |> filter_status(opts)
    |> repo().all()
  end

  @doc "Fetches a defect reason by UUID. Returns `nil` if not found."
  @spec get_defect_reason(String.t()) :: DefectReason.t() | nil
  def get_defect_reason(uuid), do: repo().get(DefectReason, uuid)

  @doc "Returns the total count of defect reasons."
  @spec count_defect_reasons(status_filter) :: non_neg_integer()
  def count_defect_reasons(opts \\ []) do
    DefectReason
    |> from(select: count())
    |> filter_status(opts)
    |> repo().one()
  end

  @doc "Creates a defect reason. Required: `:name`. Optional: `:description`, `:status`, `:data`."
  @spec create_defect_reason(map(), opts) ::
          {:ok, DefectReason.t()} | {:error, Ecto.Changeset.t()}
  def create_defect_reason(attrs, opts \\ []) do
    %DefectReason{}
    |> DefectReason.changeset(attrs)
    |> repo().insert()
    |> log_activity("defect_reason.created", opts)
  end

  @doc "Updates a defect reason with the given attributes."
  @spec update_defect_reason(DefectReason.t(), map(), opts) ::
          {:ok, DefectReason.t()} | {:error, Ecto.Changeset.t()}
  def update_defect_reason(%DefectReason{} = defect_reason, attrs, opts \\ []) do
    defect_reason
    |> DefectReason.changeset(attrs)
    |> repo().update()
    |> log_activity("defect_reason.updated", opts)
  end

  @doc "Hard-deletes a defect reason."
  @spec delete_defect_reason(DefectReason.t(), opts) ::
          {:ok, DefectReason.t()} | {:error, Ecto.Changeset.t()}
  def delete_defect_reason(%DefectReason{} = defect_reason, opts \\ []) do
    defect_reason
    |> repo().delete()
    |> log_activity("defect_reason.deleted", opts)
  end

  @doc "Returns an `Ecto.Changeset` for tracking defect reason changes."
  @spec change_defect_reason(DefectReason.t(), map()) :: Ecto.Changeset.t()
  def change_defect_reason(%DefectReason{} = defect_reason, attrs \\ %{}) do
    DefectReason.changeset(defect_reason, attrs)
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
  # Activity logging helpers (private copy of Machines'/Operations'
  # pattern — see moduledoc for why standalone contexts don't share a
  # mixin)
  # ═══════════════════════════════════════════════════════════════════

  # Pipe-step: logs on {:ok, struct} with full metadata; on
  # {:error, changeset} logs a `db_pending: true` audit row so the
  # user-initiated action survives even when the primary write fails.
  # Passes the original tuple through unchanged.
  defp log_activity({:ok, %DefectReason{} = defect_reason} = ok, action, opts) do
    maybe_log_activity(action, defect_reason.uuid, opts, defect_reason_metadata(defect_reason))
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

  defp defect_reason_metadata(%DefectReason{} = d) do
    %{"name" => d.name, "status" => d.status}
  end
end
