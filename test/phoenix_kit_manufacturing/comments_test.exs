defmodule PhoenixKitManufacturing.CommentsTest do
  @moduledoc """
  Pure unit tests for `PhoenixKitManufacturing.Comments`. `available?/0` (and
  everything that calls it) degrades to a safe default when the DB is
  unreachable — see its `rescue`/precedent in `PhoenixKitComments.enabled?/0`
  — so these run without a test database, same as `AttachmentsTest`.
  """

  use ExUnit.Case, async: true

  alias PhoenixKitManufacturing.Comments

  describe "resource_type/1" do
    test "maps :machine to the \"machine\" resource_type string" do
      assert Comments.resource_type(:machine) == "machine"
    end
  end

  describe "available?/0" do
    test "returns a boolean without raising, DB or not" do
      assert is_boolean(Comments.available?())
    end
  end

  describe "count/2" do
    test "returns a non-negative integer without raising" do
      assert Comments.count(:machine, Ecto.UUID.generate()) >= 0
    end
  end

  describe "counts/2" do
    test "empty uuid list short-circuits to an empty map" do
      assert Comments.counts(:machine, []) == %{}
    end

    test "non-empty list returns a map without raising" do
      assert is_map(Comments.counts(:machine, [Ecto.UUID.generate()]))
    end
  end

  describe "subscribe/2 and unsubscribe/2" do
    test "always return :ok, DB or not" do
      uuid = Ecto.UUID.generate()
      assert Comments.subscribe(:machine, [uuid]) == :ok
      assert Comments.unsubscribe(:machine, [uuid]) == :ok
    end
  end
end
