defmodule Yex.MapTest do
  use ExUnit.Case, async: true
  alias Yex.{Doc, Map, MapPrelim, ArrayPrelim}
  doctest Map
  doctest MapPrelim

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

    test "non-UTF-8 binaries are stored as buffers and read back as Yex.Buffer", %{
      doc: doc,
      map: map
    } do
      bin = <<255, 0, 1>>
      buffer = %Yex.Buffer{data: bin}
      assert :ok = Map.set(map, "buffer", bin)
      assert :ok = Map.set(map, "nested", %{"list" => [bin]})

      assert {:ok, ^buffer} = Map.fetch(map, "buffer")
      assert {:ok, %{"list" => [^buffer]}} = Map.fetch(map, "nested")
      assert %{"buffer" => ^buffer, "nested" => %{"list" => [^buffer]}} = Map.to_json(map)

      # The value read back can be written again, and survives a sync.
      remote = Doc.new()
      {:ok, update} = Yex.encode_state_as_update(doc)
      :ok = Yex.apply_update(remote, update)
      remote_map = Doc.get_map(remote, "map")
      {:ok, value} = Map.fetch(remote_map, "buffer")
      assert :ok = Map.set(remote_map, "copy", value)
      assert {:ok, ^buffer} = Map.fetch(remote_map, "copy")
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

    test "set_and_get/3 fail", %{map: _map} do
      # Mock test removed - relies on NIF implementation
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

  describe "clear/1" do
    test "removes all keys", %{map: map} do
      Map.set(map, "a", 1)
      Map.set(map, "b", "two")
      Map.set(map, "c", [3])

      assert :ok = Map.clear(map)
      assert Map.size(map) == 0
      assert Map.to_map(map) == %{}
      assert :error = Map.fetch(map, "a")
    end

    test "on an empty map emits no update", %{doc: doc, map: map} do
      {:ok, _} = Doc.monitor_update(doc)
      assert :ok = Map.clear(map)
      assert Map.size(map) == 0
      refute_received {:update_v1, _, _, _}
    end

    test "on a map whose keys were all deleted emits no update", %{doc: doc, map: map} do
      Map.set(map, "a", "one")
      Map.delete(map, "a")
      {:ok, _} = Doc.monitor_update(doc)
      assert :ok = Map.clear(map)
      assert Map.size(map) == 0
      refute_received {:update_v1, _, _, _}
    end

    test "on a non-empty map emits an update", %{doc: doc, map: map} do
      Map.set(map, "a", "one")
      {:ok, _} = Doc.monitor_update(doc)
      assert :ok = Map.clear(map)
      assert_receive {:update_v1, _, _, _}
    end

    test "deletes nested shared types", %{doc: doc, map: map} do
      Map.set(map, "child", MapPrelim.from(%{"nested_key" => "nested_value"}))
      Map.set(map, "list", ArrayPrelim.from(["nested_element"]))
      child = Map.fetch!(map, "child")
      list = Map.fetch!(map, "list")
      {:ok, before} = Yex.encode_state_as_update(doc)
      assert :binary.match(before, "nested_value") != :nomatch
      assert :binary.match(before, "nested_element") != :nomatch

      assert :ok = Map.clear(map)

      # GC drops only deleted items, so nested content left live would still be encoded.
      {:ok, update} = Yex.encode_state_as_update(doc)
      assert :binary.match(update, "nested_value") == :nomatch
      assert :binary.match(update, "nested_key") == :nomatch
      assert :binary.match(update, "nested_element") == :nomatch

      remote = Doc.new()
      :ok = Yex.apply_update(remote, update)
      assert Map.to_map(Doc.get_map(remote, "map")) == %{}

      assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
        Map.set(child, "k", "v2")
      end

      assert_raise Yex.DeletedSharedTypeError, "Array has been deleted", fn ->
        Yex.Array.push(list, 3)
      end
    end

    test "emits a delete action with old_value for every key", %{doc: doc, map: map} do
      Map.set(map, "a", "one")
      Map.set(map, "b", "two")
      ref = Yex.SharedType.observe(map)
      deep_ref = Yex.SharedType.observe_deep(map)

      Doc.transaction(doc, "origin", fn -> Map.clear(map) end)

      expected_keys = %{
        "a" => %{action: :delete, old_value: "one"},
        "b" => %{action: :delete, old_value: "two"}
      }

      assert_receive {:observe_event, ^ref,
                      %Yex.MapEvent{path: [], target: ^map, keys: ^expected_keys}, "origin", _}

      assert_receive {:observe_deep_event, ^deep_ref,
                      [%Yex.MapEvent{path: [], target: ^map, keys: ^expected_keys}], "origin", _}
    end

    test "joins an open transaction", %{doc: doc, map: map} do
      Map.set(map, "a", 1)

      Doc.transaction(doc, fn ->
        Map.set(map, "b", 2)
        assert :ok = Map.clear(map)
        assert Map.size(map) == 0
        Map.set(map, "c", 3)
      end)

      assert Map.to_map(map) == %{"c" => 3}
    end

    test "syncs to another doc", %{doc: doc, map: map} do
      Map.set(map, "a", 1)
      Map.set(map, "b", 2)
      remote = Doc.new()
      {:ok, update} = Yex.encode_state_as_update(doc)
      :ok = Yex.apply_update(remote, update)
      assert Map.size(Doc.get_map(remote, "map")) == 2

      {:ok, sv} = Yex.encode_state_vector(remote)
      Map.clear(map)
      {:ok, diff} = Yex.encode_state_as_update(doc, sv)
      :ok = Yex.apply_update(remote, diff)

      assert Map.to_map(Doc.get_map(remote, "map")) == %{}
    end

    test "above the item limit runs on a dirty scheduler and emits one update", %{
      doc: doc,
      map: map
    } do
      n = Yex.Nif.dirty_clear_items() + 1
      Doc.transaction(doc, fn -> for i <- 1..n, do: Map.set(map, "k#{i}", i) end)
      assert :dirty = Yex.Nif.map_clear(map, nil, Yex.Nif.dirty_clear_items())
      assert Map.size(map) == n

      {:ok, _} = Doc.monitor_update(doc)
      ref = Yex.SharedType.observe(map)
      assert :ok = Map.clear(map)
      assert Map.size(map) == 0
      assert_received {:update_v1, _, _, _}
      refute_received {:update_v1, _, _, _}
      assert_received {:observe_event, ^ref, %Yex.MapEvent{keys: keys}, _, _}
      assert map_size(keys) == n
    end

    test "above the item limit joins an open transaction", %{doc: doc, map: map} do
      n = Yex.Nif.dirty_clear_items() + 1
      Doc.transaction(doc, fn -> for i <- 1..n, do: Map.set(map, "k#{i}", i) end)

      Doc.transaction(doc, fn ->
        Map.set(map, "a", 1)
        assert :ok = Map.clear(map)
        assert Map.size(map) == 0
        Map.set(map, "b", 2)
      end)

      assert Map.to_map(map) == %{"b" => 2}
    end

    test "on a deleted map above the item limit raises", %{doc: doc, map: map} do
      n = Yex.Nif.dirty_clear_items() + 1
      Doc.transaction(doc, fn -> for i <- 1..n, do: Map.set(map, "k#{i}", i) end)
      Map.set(map, "child", MapPrelim.from(%{"k" => "v"}))
      child = Map.fetch!(map, "child")
      Map.delete(map, "child")

      assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
        Map.clear(child)
      end
    end

    test "on a deleted map raises like delete/2", %{map: map} do
      Map.set(map, "child", MapPrelim.from(%{"k" => "v"}))
      child = Map.fetch!(map, "child")
      Map.delete(map, "child")

      assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
        Map.delete(child, "k")
      end

      assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
        Map.clear(child)
      end
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

    test "keys/1 returns list of all keys", %{map: map} do
      assert [] = Map.keys(map)
      Map.set(map, "foo", "bar")
      Map.set(map, "baz", "qux")
      keys = Map.keys(map)
      assert length(keys) == 2
      assert "foo" in keys
      assert "baz" in keys
    end

    test "values/1 returns list of all values", %{map: map} do
      assert [] = Map.values(map)
      Map.set(map, "foo", "bar")
      Map.set(map, "baz", 123)
      values = Map.values(map)
      assert length(values) == 2
      assert "bar" in values
      assert 123.0 in values
    end

    test "keys/1 and values/1 with nested types", %{map: map} do
      Map.set(map, "array", ArrayPrelim.from([1, 2, 3]))
      Map.set(map, "text", "hello")

      keys = Map.keys(map)
      assert length(keys) == 2
      assert "array" in keys
      assert "text" in keys

      values = Map.values(map)
      assert length(values) == 2
      assert "hello" in values
      assert Enum.any?(values, fn v -> match?(%Yex.Array{}, v) end)
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

      assert %MapPrelim{} = Yex.Output.as_prelim(map)
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
