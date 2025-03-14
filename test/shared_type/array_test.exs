defmodule Yex.ArrayTest do
  use ExUnit.Case
  alias Yex.{Doc, Array, ArrayPrelim, SharedType}
  doctest Array
  doctest ArrayPrelim

  setup do
    doc = Doc.new()
    array = Doc.get_array(doc, "array")
    {:ok, doc: doc, array: array}
  end

  describe "basic array operations" do
    test "insert/3 adds element at specified position", %{array: array} do
      assert :ok = Array.insert(array, 0, "first")
      assert :ok = Array.insert(array, 1, "second")
      assert :ok = Array.insert(array, 1, "middle")
      assert ["first", "middle", "second"] = Array.to_list(array)
    end

    test "insert_list/3 adds multiple elements", %{array: array} do
      assert :ok = Array.insert_list(array, 0, [1, 2, 3, 4, 5])
      assert [1, 2, 3, 4, 5] = Array.to_json(array)
    end

    test "push/2 adds element at the end", %{array: array} do
      Array.push(array, "first")
      Array.push(array, "second")
      assert ["first", "second"] = Array.to_list(array)
    end

    test "unshift/2 adds element at the beginning", %{array: array} do
      Array.unshift(array, "second")
      Array.unshift(array, "first")
      assert ["first", "second"] = Array.to_list(array)
    end

    test "delete/2 removes element at index", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3])
      assert :ok = Array.delete(array, 1)
      assert [1, 3] = Array.to_list(array)
    end

    test "delete_range/3 removes elements in range", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3, 4, 5])
      assert :ok = Array.delete_range(array, 1, 3)
      assert [1, 5] = Array.to_list(array)
    end

    test "delete_range/3 with negative index", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3, 4, 5])
      assert :ok = Array.delete_range(array, -3, 2)
      assert [1, 2, 5] = Array.to_list(array)
    end

    test "move_to/3 moves element to new position", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3, 4])
      assert :ok = Array.move_to(array, 0, 2)
      assert [2, 1, 3, 4] = Array.to_list(array)
    end
  end

  describe "access operations" do
    test "fetch/2 gets element at index", %{array: array} do
      Array.push(array, "Hello")
      assert {:ok, "Hello"} = Array.fetch(array, 0)
      assert :error = Array.fetch(array, 1)
    end

    test "fetch/2 with negative index", %{array: array} do
      Array.push(array, "Hello")
      Array.push(array, "World")
      assert {:ok, "World"} = Array.fetch(array, -1)
    end

    test "fetch!/2 gets element or raises", %{array: array} do
      Array.push(array, "Hello")
      assert "Hello" = Array.fetch!(array, 0)
      assert_raise ArgumentError, fn -> Array.fetch!(array, 1) end
    end

    test "deprecated get/2 still works", %{array: array} do
      Array.push(array, "Hello")
      assert {:ok, "Hello"} = Array.get(array, 0)
    end
  end

  describe "utility functions" do
    test "to_list/1 returns list representation", %{array: array} do
      Array.insert_list(array, 0, ["Hello", "World"])
      assert ["Hello", "World"] = Array.to_list(array)
    end

    test "length/1 returns array size", %{array: array} do
      assert 0 = Array.length(array)
      Array.push(array, "Hello")
      assert 1 = Array.length(array)
    end

    test "to_json/1 returns JSON-compatible format", %{array: array} do
      Array.insert_list(array, 0, ["Hello", "World"])
      assert ["Hello", "World"] = Array.to_json(array)
    end

    test "member?/2 checks if element exists", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3])
      assert Array.member?(array, 2)
      refute Array.member?(array, 4)
    end
  end

  describe "ArrayPrelim" do
    test "from/1 creates ArrayPrelim from list" do
      prelim = ArrayPrelim.from(["Hello", "World"])
      assert %ArrayPrelim{list: ["Hello", "World"]} = prelim
    end

    test "from/1 works with any enumerable" do
      prelim = ArrayPrelim.from(1..3)
      assert %ArrayPrelim{list: [1, 2, 3]} = prelim
    end
  end

  describe "as_prelim" do
    test "converts Array to ArrayPrelim", %{array: array} do
      Array.insert_list(array, 0, ["Hello", "World"])
      prelim = Array.as_prelim(array)
      assert %ArrayPrelim{list: ["Hello", "World"]} = prelim
    end
  end

  describe "Enumerable protocol" do
    test "implements count", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3])
      assert {:ok, 3} = Enumerable.count(array)
    end

    test "implements member?", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3])
      assert {:ok, true} = Enumerable.member?(array, 2)
      assert {:ok, false} = Enumerable.member?(array, 4)
    end

    test "implements slice", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3, 4, 5])
      {:ok, 5, fun} = Enumerable.slice(array)
      assert [2, 3] = fun.(1, 2)
    end

    test "implements reduce", %{array: array} do
      Array.insert_list(array, 0, [1, 2, 3])
      assert 6 = Enum.reduce(array, 0, &(&1 + &2))
    end
  end

  test "compare" do
    doc = Doc.new()

    array1 = Doc.get_array(doc, "array")
    array2 = Doc.get_array(doc, "array")

    assert array1 == array2
  end

  test "delete" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.push(array, "Hello1")
    Array.push(array, "Hello2")
    assert :ok == Array.delete(array, 0)
    assert ["Hello2"] == Array.to_list(array)
  end

  test "delete_range" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.push(array, "1")
    Array.push(array, "2")
    Array.push(array, "3")
    Array.push(array, "4")
    Array.push(array, "5")
    assert :ok == Array.delete_range(array, 0, 2)
    assert ["3", "4", "5"] == Array.to_list(array)
  end

  test "delete_range out of bounds" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.push(array, "1")
    Array.push(array, "2")
    assert :error == Array.delete_range(array, 0, 3)
  end

  test "delete with minus" do
    doc = Doc.new()
    array = Doc.get_array(doc, "array")
    Array.push(array, "1")
    Array.push(array, "2")
    Array.push(array, "3")
    Array.push(array, "4")
    Array.push(array, "5")
    assert :ok == Array.delete(array, -1)
    assert ["1", "2", "3", "4"] == Array.to_list(array)
  end

  test "ArrayPrelim" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.insert(array, 0, ArrayPrelim.from(["Hello"]))
    assert [inner_aray = %Array{}] = Array.to_list(array)
    assert ["Hello"] == Array.to_list(inner_aray)

    assert 1 == Array.length(array)
  end

  test "to_json" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.insert(array, 0, ArrayPrelim.from(["Hello"]))
    Array.insert(array, 1, ArrayPrelim.from(["Hello2"]))
    assert [["Hello"], ["Hello2"]] = Array.to_json(array)
  end

  test "transaction" do
    doc = Doc.new()

    array = Doc.get_array(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        Array.insert(array, 0, "Hello")
        Array.insert(array, 0, "Hello")
      end)

    #    assert "HelloHello" == Array.to_string(array)
    assert 2 == Array.length(array)
  end

  test "move_to" do
    doc = Yex.Doc.new()
    array = Yex.Doc.get_array(doc, "array")
    Yex.Array.push(array, Yex.ArrayPrelim.from([1, 2]))
    Yex.Array.push(array, Yex.ArrayPrelim.from([3, 4]))
    Yex.Array.push(array, Yex.ArrayPrelim.from([5, 6]))
    :ok = Yex.Array.move_to(array, 0, 2)
    assert [[3, 4], [1, 2], [5, 6]] == Yex.Array.to_json(array)
    :ok = Yex.Array.move_to(array, 0, 2)
    assert [[1, 2], [3, 4], [5, 6]] == Yex.Array.to_json(array)
    :ok = Yex.Array.move_to(array, 1, 3)
    assert [[1, 2], [5, 6], [3, 4]] == Yex.Array.to_json(array)
    :ok = Yex.Array.move_to(array, 2, 1)
    assert [[1, 2], [3, 4], [5, 6]] == Yex.Array.to_json(array)
    :ok = Yex.Array.move_to(array, 2, 0)
    assert [[5, 6], [1, 2], [3, 4]] == Yex.Array.to_json(array)
  end

  test "monitor move_to update" do
    doc = Yex.Doc.new()
    array = Yex.Doc.get_array(doc, "array")
    Yex.Array.push(array, Enum.to_list(1..100))
    Yex.Array.push(array, Enum.to_list(101..200))
    Yex.Array.push(array, Enum.to_list(201..300))
    {:ok, _monitor_ref} = Doc.monitor_update(doc)
    :ok = Yex.Array.move_to(array, 0, 2)
    assert_receive {:update_v1, update, _, ^doc}
    # The update should be smaller than adding and removing elements.
    assert byte_size(update) < 50
  end

  test "out of bounds" do
    doc = Yex.Doc.new()
    array = Yex.Doc.get_array(doc, "array")
    Yex.Array.push(array, Enum.to_list(1..100))
    Yex.Array.push(array, Enum.to_list(101..200))
    Yex.Array.push(array, Enum.to_list(201..300))
    :error = Yex.Array.move_to(array, 0, 5)
    :error = Yex.Array.move_to(array, 3, 0)
  end

  describe "observe" do
    test "insert " do
      doc = Doc.new()

      array = Doc.get_array(doc, "text")

      ref = SharedType.observe(array)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Array.insert(array, 0, "Hello")
          Array.insert(array, 1, " World")
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.ArrayEvent{
                        change: [%{insert: ["Hello", " World"]}]
                      }, "origin_value", nil}
    end

    test "delete " do
      doc = Doc.new()

      array = Doc.get_array(doc, "text")
      Array.insert(array, 0, "Hello")
      Array.insert(array, 1, " World")

      ref = SharedType.observe(array)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Array.delete(array, 0)
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.ArrayEvent{
                        change: [%{delete: 1}]
                      }, "origin_value", nil}
    end

    test "retain and insert" do
      doc = Doc.new()

      array = Doc.get_array(doc, "text")
      Array.insert(array, 0, "Hello")

      ref = SharedType.observe(array)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Array.insert(array, 1, " World")
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.ArrayEvent{
                        change: [%{retain: 1}, %{insert: [" World"]}]
                      }, "origin_value", nil}
    end

    test "unobserve" do
      doc = Doc.new()

      array = Doc.get_array(doc, "text")

      ref = SharedType.observe(array)
      assert :ok = SharedType.unobserve(ref)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Array.insert(array, 0, "Hello")
        end)

      refute_receive {:observe_event, _, %Yex.ArrayEvent{}, _}

      # noop but return ok
      assert :ok = SharedType.unobserve(make_ref())
    end
  end

  test "observe_deep" do
    doc = Doc.new()
    array = Doc.get_array(doc, "data")

    Array.insert(
      array,
      0,
      Yex.MapPrelim.from(%{
        "key" => Yex.MapPrelim.from(%{"key" => ArrayPrelim.from([1, 2, 3, 4])})
      })
    )

    ref = SharedType.observe_deep(array)

    map = Yex.Array.fetch!(array, 0)
    child_map = Yex.Map.fetch!(map, "key")

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Yex.Array.push(array, "array_value")
        Yex.Map.set(child_map, "key2", "value")
        Yex.Map.set(map, "key2", "value")
      end)

    assert_receive {:observe_deep_event, ^ref,
                    [
                      %Yex.ArrayEvent{
                        path: [],
                        target: ^array,
                        change: [%{retain: 1}, %{insert: ["array_value"]}]
                      },
                      %Yex.MapEvent{
                        path: [0],
                        target: ^map,
                        keys: %{"key2" => %{action: :add, new_value: "value"}}
                      },
                      %Yex.MapEvent{
                        path: [0, "key"],
                        target: ^child_map,
                        keys: %{"key2" => %{action: :add, new_value: "value"}}
                      }
                    ], "origin_value", nil}
  end

  test "unobserve_deep" do
    doc = Doc.new()

    array = Doc.get_array(doc, "text")

    ref = SharedType.observe_deep(array)
    assert :ok = SharedType.unobserve_deep(ref)

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Array.insert(array, 0, "Hello")
      end)

    refute_receive {:observe_deep_event, _, %Yex.ArrayEvent{}, _, _}

    # noop but return ok
    assert :ok = SharedType.unobserve_deep(make_ref())
  end

  describe "Enum protocol" do
    test "count" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, "Hello1")
      Array.push(array, "Hello2")
      assert 2 == Enum.count(array)
    end

    test "to_list" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, "Hello1")
      Array.push(array, "Hello2")
      assert Array.to_list(array) == Enum.to_list(array)
    end

    test "member?" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, "Hello1")
      Array.push(array, "Hello2")
      assert Enum.member?(array, "Hello1")
    end

    test "fetch!" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, "Hello1")
      Array.push(array, "Hello2")
      assert "Hello2" == Enum.fetch!(array, 1)
    end

    test "all?" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, true)
      Array.push(array, true)
      assert Enum.all?(array)
    end

    test "any?" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, true)
      Array.push(array, false)
      assert Enum.any?(array)
    end

    test "map" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, 1)
      Array.push(array, 2)
      assert Enum.map(array, fn v -> v * 2 end) |> Enum.to_list() == [2, 4]
    end

    test "slice" do
      doc = Doc.new()

      array = Doc.get_array(doc, "array")

      Array.push(array, 1)
      Array.push(array, 2)
      Array.push(array, 3)

      assert Enum.slice(array, 0, 1) |> Enum.to_list() == [1]
      assert Enum.slice(array, 2, 3) |> Enum.to_list() == [3]
    end
  end
end
