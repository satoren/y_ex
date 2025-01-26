defmodule Yex.MapTest do
  use ExUnit.Case
  alias Yex.{Doc, Map, MapPrelim, SharedType}
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

  test "has_key?" do
    doc = Doc.new()

    map = Doc.get_map(doc, "map")

    Map.set(map, "key", "Hello1")
    Map.set(map, "key2", "Hello2")
    assert Map.has_key?(map, "key")
    assert Map.has_key?(map, "key2")
    refute Map.has_key?(map, "key3")
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

  describe "observe" do
    test "set " do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      ref = SharedType.observe(map)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Map.set(map, "0", "Hello")
          Map.set(map, "1", " World")
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.MapEvent{
                        target: ^map,
                        keys: %{
                          "0" => %{action: :add, new_value: "Hello"},
                          "1" => %{action: :add, new_value: " World"}
                        }
                      }, "origin_value", nil}
    end

    test "delete " do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")
      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")

      ref = SharedType.observe(map)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Map.delete(map, "0")
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.MapEvent{
                        target: ^map,
                        keys: %{"0" => %{action: :delete, old_value: "Hello"}}
                      }, "origin_value", nil}
    end

    test "unobserve" do
      doc = Doc.new()

      map = Doc.get_map(doc, "text")

      ref = SharedType.observe(map)
      assert :ok = SharedType.unobserve(ref)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Map.set(map, "0", "Hello")
        end)

      refute_receive {:observe_event, _, %Yex.MapEvent{}, _}

      # noop but return ok
      assert :ok = SharedType.unobserve(make_ref())
    end
  end

  test "observe_deep" do
    doc = Doc.new()
    map = Doc.get_map(doc, "data")

    Map.set(
      map,
      "key1",
      Yex.MapPrelim.from(%{
        "key2" => Yex.MapPrelim.from(%{"key3" => Yex.ArrayPrelim.from([1, 2, 3, 4])})
      })
    )

    ref = SharedType.observe_deep(map)

    child_map = Yex.Map.fetch!(map, "key1")
    child_map2 = Yex.Map.fetch!(child_map, "key2")
    child_array = Yex.Map.fetch!(child_map2, "key3")

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Yex.Array.push(child_array, 5)
        Yex.Map.set(child_map, "set1", "value1")
        Yex.Map.set(map, "set2", "value2")
      end)

    assert_receive {:observe_deep_event, ^ref,
                    [
                      %Yex.MapEvent{
                        path: [],
                        target: ^map,
                        keys: %{"set2" => %{action: :add, new_value: "value2"}}
                      },
                      %Yex.MapEvent{
                        path: ["key1"],
                        target: ^child_map,
                        keys: %{"set1" => %{action: :add, new_value: "value1"}}
                      },
                      %Yex.ArrayEvent{
                        change: [%{retain: 4}, %{insert: [5]}],
                        path: ["key1", "key2", "key3"],
                        target: ^child_array
                      }
                    ], "origin_value", _metadata}
  end

  test "unobserve_deep" do
    doc = Doc.new()

    map = Doc.get_map(doc, "text")

    ref = SharedType.observe_deep(map)
    assert :ok = SharedType.unobserve_deep(ref)

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Map.set(map, "0", "Hello")
      end)

    refute_receive {:observe_deep_event, _, %Yex.MapEvent{}, _, _}

    # noop but return ok
    assert :ok = SharedType.unobserve_deep(make_ref())
  end

  describe "Enum protocol" do
    test "count" do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")
      assert 2 == Enum.count(map)
    end

    test "to_list" do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")
      assert Map.to_list(map) == Enum.to_list(map)
    end

    test "slice" do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")
      assert [{"0", "Hello"}] == Enum.slice(map, 0, 1)
      assert [{"1", " World"}] == Enum.slice(map, 1, 2)
    end

    test "member?" do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")
      assert Enum.member?(map, {"0", "Hello"})
    end

    test "fetch!" do
      doc = Doc.new()

      map = Doc.get_map(doc, "map")

      Map.set(map, "0", "Hello")
      Map.set(map, "1", " World")
      assert {"0", "Hello"} == Enum.fetch!(map, 0)
    end
  end
end
