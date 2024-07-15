defmodule Yex.ArrayTest do
  use ExUnit.Case
  alias Yex.{Doc, Array, ArrayPrelim}
  doctest Doc

  test "insert" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.insert(array, 0, "Hello")
    assert 1 == Array.length(array)
  end

  test "push" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.push(array, "Hello1")
    Array.push(array, "Hello2")
    assert ["Hello1", "Hello2"] == Array.to_list(array)
    assert 2 == Array.length(array)
  end

  test "get" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.push(array, "Hello1")
    Array.push(array, "Hello2")
    assert {:ok, "Hello1"} == Array.get(array, 0)
    assert {:ok, "Hello2"} == Array.get(array, 1)
  end

  test "unshift" do
    doc = Doc.new()

    array = Doc.get_array(doc, "array")

    Array.unshift(array, "Hello1")
    Array.unshift(array, "Hello2")
    assert ["Hello2", "Hello1"] == Array.to_list(array)
    assert 2 == Array.length(array)
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
end
