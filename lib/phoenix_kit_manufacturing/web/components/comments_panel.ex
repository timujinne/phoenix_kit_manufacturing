defmodule PhoenixKitManufacturing.Web.Components.CommentsPanel do
  @moduledoc """
  Presentation helper for Manufacturing resource comment threads. `panel/1`
  embeds the ready-made `PhoenixKitComments.Web.CommentsComponent`.

  A 1:1 adaptation of `PhoenixKitWarehouse.Web.Components.CommentsPanel`,
  narrowed to the single `kind :: :machine` this module wires up today —
  mirrors `PhoenixKitManufacturing.Comments`' own parameterization.

  Callers guard visibility with `PhoenixKitManufacturing.Comments.available?/0`.
  """
  use Phoenix.Component

  alias PhoenixKitManufacturing.Comments

  @doc """
  Embedded comments thread for a Manufacturing resource.

  Assigns:
    * `:kind` — `:machine` (required)
    * `:resource_uuid` — the resource's uuid, used as `resource_uuid`
      (required)
    * `:current_user` — current user struct (or nil) (required)
    * `:id` — optional DOM id; defaults to `comments-<kind>-<uuid>`
    * `:title` — optional heading; defaults to `""`
    * `:read_only` — when true, render without composer or chrome
  """
  attr(:kind, :atom, required: true, values: [:machine])
  attr(:resource_uuid, :string, required: true)
  attr(:current_user, :any, required: true)
  attr(:id, :string, default: nil)
  attr(:title, :string, default: "")
  attr(:read_only, :boolean, default: false)

  def panel(assigns) do
    assigns =
      assigns
      |> assign(:id, assigns.id || "comments-#{assigns.kind}-#{assigns.resource_uuid}")
      |> assign(:composer_position, if(assigns.read_only, do: nil, else: :top))
      |> assign(:show_chrome, not assigns.read_only)

    ~H"""
    <.live_component
      module={PhoenixKitComments.Web.CommentsComponent}
      id={@id}
      resource_type={Comments.resource_type(@kind)}
      resource_uuid={@resource_uuid}
      current_user={@current_user}
      title={@title}
      show_title={@show_chrome}
      show_likes={@show_chrome}
      composer_position={@composer_position}
    />
    """
  end
end
