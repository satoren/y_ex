defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, Array, UndoManager}
  doctest Yex.UndoManager

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")


    # Return these as the test context
    {:ok, doc: doc, text: text, array: array, map: map}
  end

  test "can create an undo manager", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    assert %UndoManager{} = undo_manager
    assert undo_manager.reference != nil
  end

  test "can undo without failure when stack is empty", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    UndoManager.undo(undo_manager)
  end

  test "can include an origin for tracking", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    origin = "test-origin"
    UndoManager.include_origin(undo_manager, origin)
  end

  test "can undo with no origin with text changes, text removed", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    inserted_text = "Hello, world!"
    Text.insert(text, 0, inserted_text)
    assert Text.to_string(text) == inserted_text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "can undo with origin and transaction with text changes, text removed", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    origin = "test-origin"
    UndoManager.include_origin(undo_manager, origin)
    inserted_text = "Hello, world!"
    Doc.transaction(doc, origin, fn ->
      Text.insert(text, 0, inserted_text)
    end)
    assert Text.to_string(text) == inserted_text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "undo only removes changes from tracked origin for text", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    # Set up our tracked origin
    tracked_origin = "tracked-origin"
    UndoManager.include_origin(undo_manager, tracked_origin)

    # Make changes from an untracked origin
    untracked_origin = "untracked-origin"
    Doc.transaction(doc, untracked_origin, fn ->
      Text.insert(text, 0, "Untracked ")
    end)

    # Make changes from our tracked origin
    Doc.transaction(doc, tracked_origin, fn ->
      Text.insert(text, 10, "changes ")
    end)

    # Make more untracked changes
    Doc.transaction(doc, untracked_origin, fn ->
      Text.insert(text, 18, "remain")
    end)

    # Initial state should have all changes
    assert Text.to_string(text) == "Untracked changes remain"

    # After undo, only tracked changes should be removed
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "Untracked remain"
  end

  test "can undo array changes", %{doc: doc, array: array} do
    # Create a new undo manager specifically for the array
    undo_manager = UndoManager.new(doc, array)

    # Insert some values
    Array.push(array, "first")
    Array.push(array, "second")
    Array.push(array, "third")

    # Verify initial state
    assert Array.to_list(array) == ["first", "second", "third"]

    # Undo the last insertion
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == []

  end

  test "can undo map changes", %{doc: doc, map: map} do
    # Create a map and its undo manager
    undo_manager = UndoManager.new(doc, map)

    # Insert some values
    Yex.Map.set(map, "key1", "value1")
    Yex.Map.set(map, "key2", "value2")
    Yex.Map.set(map, "key3", "value3")

    # Verify initial state
    assert Yex.Map.to_map(map) == %{"key1" => "value1", "key2" => "value2", "key3" => "value3"}

    # Undo all changes
    UndoManager.undo(undo_manager)
    assert Yex.Map.to_map(map) == %{}
  end

  test "undo only removes changes from tracked origin for array", %{doc: doc, array: array} do
    # Create a new undo manager specifically for the array
    undo_manager = UndoManager.new(doc, array)
    tracked_origin = "tracked-origin"
    UndoManager.include_origin(undo_manager, tracked_origin)

    # Make changes from an untracked origin
    untracked_origin = "untracked-origin"
    Doc.transaction(doc, untracked_origin, fn ->
      Array.push(array, "untracked1")
      Array.push(array, "untracked2")
    end)

    # Make changes from tracked origin
    Doc.transaction(doc, tracked_origin, fn ->
      Array.push(array, "tracked1")
      Array.push(array, "tracked2")
    end)

    # More untracked changes
    Doc.transaction(doc, untracked_origin, fn ->
      Array.push(array, "untracked3")
    end)

    # Verify initial state
    assert Array.to_list(array) == ["untracked1", "untracked2", "tracked1", "tracked2", "untracked3"]

    # After undo, only tracked changes should be removed
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == ["untracked1", "untracked2", "untracked3"]
  end

  test "undo only removes changes from tracked origin for map", %{doc: doc, map: map} do
    undo_manager = UndoManager.new(doc, map)
    tracked_origin = "tracked-origin"
    UndoManager.include_origin(undo_manager, tracked_origin)

    # Make changes from an untracked origin
    untracked_origin = "untracked-origin"
    Doc.transaction(doc, untracked_origin, fn ->
      Yex.Map.set(map, "untracked1", "value1")
      Yex.Map.set(map, "untracked2", "value2")
    end)

    # Make changes from tracked origin in a single transaction
    Doc.transaction(doc, tracked_origin, fn ->
      Yex.Map.set(map, "tracked1", "value3")
      Yex.Map.set(map, "tracked2", "value4")
    end)

    # More untracked changes in a single transaction
    Doc.transaction(doc, untracked_origin, fn ->
      Yex.Map.set(map, "untracked3", "value5")
    end)

    # Let's ensure all transactions are complete before proceeding
    Process.sleep(10)

    # Verify initial state
    expected_initial = %{
      "untracked1" => "value1",
      "untracked2" => "value2",
      "tracked1" => "value3",
      "tracked2" => "value4",
      "untracked3" => "value5"
    }
    assert Yex.Map.to_map(map) == expected_initial

    # After undo, only tracked changes should be removed
    UndoManager.undo(undo_manager)

    # Give time for the undo operation to complete
    Process.sleep(10)

    expected_after_undo = %{
      "untracked1" => "value1",
      "untracked2" => "value2",
      "untracked3" => "value5"
    }
    assert Yex.Map.to_map(map) == expected_after_undo
  end

end
