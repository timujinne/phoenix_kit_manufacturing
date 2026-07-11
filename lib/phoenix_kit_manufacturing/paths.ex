defmodule PhoenixKitManufacturing.Paths do
  @moduledoc """
  Centralized path helpers for the Manufacturing module.

  All paths go through `PhoenixKit.Utils.Routes.path/1` for prefix/locale
  handling. Never hardcode `"/admin/manufacturing"` in a LiveView or template
  — use these helpers instead so URL prefix changes only need updating here.
  """

  alias PhoenixKit.Utils.Routes

  @base "/admin/manufacturing"

  @doc "Manufacturing dashboard (module landing)."
  @spec index() :: String.t()
  def index, do: Routes.path(@base)

  # ── Machines ────────────────────────────────────────────────────────

  @doc "Machines list."
  @spec machines() :: String.t()
  def machines, do: Routes.path("#{@base}/machines")

  @doc "New machine form."
  @spec machine_new() :: String.t()
  def machine_new, do: Routes.path("#{@base}/machines/new")

  @doc "Edit machine form."
  @spec machine_edit(String.t()) :: String.t()
  def machine_edit(uuid), do: Routes.path("#{@base}/machines/#{uuid}/edit")

  @doc "Machine card, Operations tab (hidden CRUD route, edit form only)."
  @spec machine_operations(String.t()) :: String.t()
  def machine_operations(uuid), do: Routes.path("#{@base}/machines/#{uuid}/operations")

  @doc "Machine card, Files tab (hidden CRUD route, edit form only)."
  @spec machine_files(String.t()) :: String.t()
  def machine_files(uuid), do: Routes.path("#{@base}/machines/#{uuid}/files")

  @doc "Machine card, Comments tab (hidden CRUD route, edit form only)."
  @spec machine_comments(String.t()) :: String.t()
  def machine_comments(uuid), do: Routes.path("#{@base}/machines/#{uuid}/comments")

  # ── Machine types ───────────────────────────────────────────────────

  @doc "Machine types list."
  @spec types() :: String.t()
  def types, do: Routes.path("#{@base}/machines/types")

  @doc "New machine type form."
  @spec type_new() :: String.t()
  def type_new, do: Routes.path("#{@base}/machines/types/new")

  @doc "Edit machine type form."
  @spec type_edit(String.t()) :: String.t()
  def type_edit(uuid), do: Routes.path("#{@base}/machines/types/#{uuid}/edit")

  # ── Operations ──────────────────────────────────────────────────────

  @doc "Operations list."
  @spec operations() :: String.t()
  def operations, do: Routes.path("#{@base}/machines/operations")

  @doc "New operation form."
  @spec operation_new() :: String.t()
  def operation_new, do: Routes.path("#{@base}/machines/operations/new")

  @doc "Edit operation form."
  @spec operation_edit(String.t()) :: String.t()
  def operation_edit(uuid), do: Routes.path("#{@base}/machines/operations/#{uuid}/edit")

  # ── Defect reasons ──────────────────────────────────────────────────

  @doc "Defect reasons list."
  @spec defect_reasons() :: String.t()
  def defect_reasons, do: Routes.path("#{@base}/machines/defect-reasons")

  @doc "New defect reason form."
  @spec defect_reason_new() :: String.t()
  def defect_reason_new, do: Routes.path("#{@base}/machines/defect-reasons/new")

  @doc "Edit defect reason form."
  @spec defect_reason_edit(String.t()) :: String.t()
  def defect_reason_edit(uuid), do: Routes.path("#{@base}/machines/defect-reasons/#{uuid}/edit")
end
