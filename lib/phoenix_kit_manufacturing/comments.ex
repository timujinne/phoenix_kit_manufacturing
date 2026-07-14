defmodule PhoenixKitManufacturing.Comments do
  @moduledoc """
  Thin isolation layer over the optional `PhoenixKitComments` module for
  Manufacturing resources.

  A simplified adaptation of `PhoenixKitWarehouse.Comments`: same
  `kind`-parameterized shape, but with a single resource kind (`:machine`)
  today. The parameterization is kept (rather than collapsing to
  machine-only functions) so a future `:operation`/`:defect_reason` kind
  can be added here without reshaping callers — mirrors the precedent.

  Every function degrades gracefully when `phoenix_kit_comments` is absent
  or disabled, so callers never special-case it.
  """
  @compile {:no_warn_undefined, PhoenixKitComments}

  @resource_types %{machine: "machine"}

  @type kind :: :machine

  @doc "The comment `resource_type` string used for the given resource kind."
  @spec resource_type(kind()) :: String.t()
  def resource_type(kind) when is_map_key(@resource_types, kind),
    do: Map.fetch!(@resource_types, kind)

  @doc "True when the comments module is installed and enabled."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(PhoenixKitComments) and PhoenixKitComments.enabled?()
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc "Comment count for one resource. Returns 0 when unavailable."
  @spec count(kind(), binary()) :: non_neg_integer()
  def count(kind, uuid) when is_binary(uuid) do
    if available?() do
      PhoenixKitComments.count_comments(resource_type(kind), uuid)
    else
      0
    end
  end

  @doc """
  Comment counts for many resources of the same kind, as a `uuid => count`
  map. Every requested uuid is present (value 0 when it has no comments).
  Returns an empty map when the module is unavailable.
  """
  @spec counts(kind(), [binary()]) :: %{optional(binary()) => non_neg_integer()}
  def counts(kind, uuids) when is_list(uuids) do
    if available?() and uuids != [] do
      PhoenixKitComments.count_comments(resource_type(kind), uuids)
    else
      %{}
    end
  end

  @doc """
  Subscribes the calling process to cross-session comment activity for the
  given resource uuids. No-op when the module is unavailable.
  """
  @spec subscribe(kind(), [binary()]) :: :ok
  def subscribe(kind, uuids) when is_list(uuids) do
    if available?() do
      Enum.each(uuids, &PhoenixKitComments.subscribe(resource_type(kind), &1))
    end

    :ok
  end

  @doc "Unsubscribes the calling process from the given resource uuids."
  @spec unsubscribe(kind(), [binary()]) :: :ok
  def unsubscribe(kind, uuids) when is_list(uuids) do
    if available?() do
      Enum.each(uuids, &PhoenixKitComments.unsubscribe(resource_type(kind), &1))
    end

    :ok
  end
end
