defmodule Yex.MapTest do
  use ExUnit.Case
  alias Yex.{Doc, Map, MapPrelim}
  doctest Map
  doctest MapPrelim

  test "set" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", "Hello")
    assert 1 == Map.size(map)
  end

  test "compare" do
    doc = Doc.new()

    map1 = Doc.get_map(doc, "map")
    map2 = Doc.get_map(doc, "map")
    map3 = Doc.get_map(doc, "map3")

    assert map1 == map2
    assert map1 != map3
  end

  test "fetch" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", "Hello1")
    Map.set(map, "key2", "Hello2")
    assert {:ok, "Hello1"} == Map.fetch(map, "key")
    assert {:ok, "Hello2"} == Map.fetch(map, "key2")
    assert :error == Map.fetch(map, "key3")
  end

  test "fetch!" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", "Hello1")
    Map.set(map, "key2", "Hello2")
    assert "Hello1" == Map.fetch!(map, "key")
    assert "Hello2" == Map.fetch!(map, "key2")

    assert_raise ArgumentError, "Key not found", fn ->
      Map.fetch!(map, "key3")
    end
  end

  test "delete" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", "Hello1")
    Map.set(map, "key2", "Hello2")
    Map.delete(map, "key2")
    assert {:ok, "Hello1"} == Map.fetch(map, "key")
    assert :error == Map.fetch(map, "key2")
  end

  test "raise error when access deleted array" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")
    Map.set(map, "key", MapPrelim.from(%{"key" => "Hello"}))
    m = Map.fetch!(map, "key")
    Map.delete(map, "key")

    assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
      Map.set(m, "key", "Hello")
    end
  end

  test "MapPrelim" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", MapPrelim.from(%{"key" => "Hello"}))
    assert {:ok, inner_map} = Map.fetch(map, "key")
    assert %{"key" => "Hello"} == Map.to_map(inner_map)

    assert 1 == Map.size(map)
  end

  test "to_json" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", MapPrelim.from(%{"key" => "Hello"}))
    Map.set(map, "key2", "Hello1")
    assert %{"key" => %{"key" => "Hello"}} = Map.to_json(map)
  end

  test "transaction" do
    doc = Doc.new()

    map = Doc.get_map(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        Map.set(map, "key", "Hello")
        Map.set(map, "key2", "Hello")
      end)

    assert 2 == Map.size(map)
  end
end
