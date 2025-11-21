defmodule Yex.MapTest do
  use ExUnit.Case
  alias Yex.{Doc, Map, MapPrelim, ArrayPrelim}

  setup do
    doc = Doc.new()
    map = Doc.get_map(doc, "map")
    {:ok, doc: doc, map: map}
  end

  describe "basic map operations" do
    test "set/3 adds key-value pair", %{map: map} do
      assert :ok = Map.set(map, "key", "value")
      assert {:ok, "value"} = Map.fetch(map, "key")
    end

    test "set_and_get/3 sets and returns the value", %{map: map} do
      assert "value" = Map.set_and_get(map, "key", "value")
      assert {:ok, "value"} = Map.fetch(map, "key")
      assert "new_value" = Map.set_and_get(map, "key", "new_value")
      assert {:ok, "new_value"} = Map.fetch(map, "key")
    end

    test "set_and_get/3 with nested types", %{map: map} do
      # Test with ArrayPrelim
      assert %Yex.Array{} =
               Map.set_and_get(map, "array", Yex.ArrayPrelim.from([1, 2, 3]))

      {:ok, array} = Map.fetch(map, "array")
      assert [1.0, 2.0, 3.0] = Yex.Array.to_json(array)

      # Test with MapPrelim
      assert %Yex.Map{} =
               Map.set_and_get(map, "nested_map", Yex.MapPrelim.from(%{"inner" => "value"}))

      {:ok, nested_map} = Map.fetch(map, "nested_map")
      assert {:ok, "value"} = Yex.Map.fetch(nested_map, "inner")
    end

    test "set/3 with big integer", %{map: map} do
      assert :ok = Map.set(map, "key", 9_223_372_036_854_775_807)
      assert {:ok, 9_223_372_036_854_775_807} = Map.fetch(map, "key")
    end

    test "set/3 with map values", %{map: map} do
      assert :ok =
               Map.set(map, "array", %{
                 "key1" => "value1",
                 "key2" => "value2"
               })

      assert {:ok, array} = Map.fetch(map, "array")
      assert %{"key1" => "value1", "key2" => "value2"} = array
    end

    test "set/3 with array", %{map: map} do
      assert :ok = Map.set(map, "array", ["Hello", "World"])
      assert {:ok, array} = Map.fetch(map, "array")
      assert ["Hello", "World"] = array
    end

    test "set/3 with complex values", %{map: map} do
      array_prelim = ArrayPrelim.from(["Hello", "World"])
      assert :ok = Map.set(map, "array", array_prelim)
      assert {:ok, array} = Map.fetch(map, "array")
      assert %Yex.Array{} = array
    end

    test "delete/2 removes key", %{map: map} do
      Map.set(map, "key", "value")
      assert :ok = Map.delete(map, "key")
      assert :error = Map.fetch(map, "key")
    end
  end

  describe "access operations" do
    test "fetch/2 gets value by key", %{map: map} do
      Map.set(map, "key", "value")
      assert {:ok, "value"} = Map.fetch(map, "key")
      assert :error = Map.fetch(map, "not_found")
    end

    test "fetch!/2 gets value or raises", %{map: map} do
      Map.set(map, "key", "value")
      assert "value" = Map.fetch!(map, "key")
      assert_raise ArgumentError, fn -> Map.fetch!(map, "not_found") end
    end

    test "get/2 returns value by key", %{map: map} do
      Map.set(map, "key", "value")
      assert "value" = Map.get(map, "key")
    end

    test "get/3 returns default value when key not found", %{map: map} do
      assert is_nil(Map.get(map, "not_found"))
      assert "default" = Map.get(map, "not_found", "default")
    end

    test "get_lazy/3 evaluates function only when key not found", %{map: map} do
      Map.set(map, "key", "value")

      # When key exists, function should not be called
      assert "value" = Map.get_lazy(map, "key", fn -> flunk("Function should not be called") end)

      # When key doesn't exist, function should be called
      assert "computed" = Map.get_lazy(map, "not_found", fn -> "computed" end)
    end

    test "has_key?/2 checks key existence", %{map: map} do
      Map.set(map, "key", "value")
      assert Map.has_key?(map, "key")
      refute Map.has_key?(map, "not_found")
    end
  end

  describe "conversion functions" do
    test "to_map/1 converts to Elixir map", %{map: map} do
      Map.set(map, "key1", "value1")
      Map.set(map, "key2", "value2")
      assert %{"key1" => "value1", "key2" => "value2"} = Map.to_map(map)
    end

    test "to_list/1 converts to key-value list", %{map: map} do
      Map.set(map, "key1", "value1")
      Map.set(map, "key2", "value2")
      assert [{"key1", "value1"}, {"key2", "value2"}] = Enum.sort(Map.to_list(map))
    end

    test "to_json/1 converts to JSON-compatible format", %{map: map} do
      array_prelim = ArrayPrelim.from(["Hello", "World"])
      Map.set(map, "array", array_prelim)
      Map.set(map, "plane", ["Hello", "World"])

      json = Map.to_json(map)

      assert %{
               "array" => ["Hello", "World"],
               "plane" => ["Hello", "World"]
             } = json
    end
  end

  describe "utility functions" do
    test "size/1 returns number of entries", %{map: map} do
      assert 0 = Map.size(map)
      Map.set(map, "key1", "value1")
      assert 1 = Map.size(map)
      Map.set(map, "key2", "value2")
      assert 2 = Map.size(map)
    end
  end

  describe "MapPrelim" do
    test "from/1 creates MapPrelim from map" do
      prelim = MapPrelim.from(%{"key" => "value"})
      assert %MapPrelim{map: %{"key" => "value"}} = prelim
    end
  end

  describe "as_prelim" do
    test "converts Map to MapPrelim", %{map: map} do
      Map.set(map, "key", "value")
      Map.set(map, "array", ArrayPrelim.from(["Hello", "World"]))
      prelim = Map.as_prelim(map)
      assert %MapPrelim{} = prelim
      assert %{"key" => "value", "array" => %ArrayPrelim{}} = prelim.map
    end
  end

  describe "Enumerable protocol" do
    test "implements count", %{map: map} do
      Map.set(map, "key1", "value1")
      Map.set(map, "key2", "value2")
      assert {:ok, 2} = Enumerable.count(map)
    end

    test "implements member? for key-value pairs", %{map: map} do
      Map.set(map, "key", "value")
      assert {:ok, true} = Enumerable.member?(map, {"key", "value"})
      assert {:ok, false} = Enumerable.member?(map, {"key", "wrong"})
      assert {:ok, false} = Enumerable.member?(map, {"not_found", "value"})
    end

    test "implements member? for non key-value pairs", %{map: map} do
      assert {:ok, false} = Enumerable.member?(map, "not_a_tuple")
    end

    test "implements slice", %{map: map} do
      Map.set(map, "key1", "value1")
      Map.set(map, "key2", "value2")
      {:ok, 2, fun} = Enumerable.slice(map)
      assert [{"key2", "value2"}] = fun.(1, 1, 1)
    end

    test "implements reduce", %{map: map} do
      Map.set(map, "key1", "value1")
      Map.set(map, "key2", "value2")
      result = Enum.reduce(map, [], fn {k, v}, acc -> [{k, v} | acc] end)
      assert [{"key1", "value1"}, {"key2", "value2"}] = Enum.sort(result)
    end
  end
end
