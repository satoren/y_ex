defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  import Mock

  alias Yex.{
    Doc,
    Text,
    TextPrelim,
    Array,
    UndoManager,
    XmlFragment,
    XmlElement,
    XmlElementPrelim,
    XmlText,
    XmlTextPrelim
  }

  doctest Yex.UndoManager

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")
    xml_fragment = Doc.get_xml_fragment(doc, "xml")
    # Return these as the test context
    {:ok, doc: doc, text: text, array: array, map: map, xml_fragment: xml_fragment}
  end

  test "can create an undo manager", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    assert %UndoManager{} = undo_manager
    assert is_reference(undo_manager.reference)
  end

  test "can undo without failure when stack is empty", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    UndoManager.undo(undo_manager)
  end

  test "can include an origin for tracking", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    origin = "test-origin"
    UndoManager.include_origin(undo_manager, origin)

    # Make changes with the tracked origin
    Doc.transaction(doc, origin, fn ->
      Text.insert(text, 0, "tracked")
    end)

    # Make changes with an untracked origin
    Doc.transaction(doc, "other-origin", fn ->
      Text.insert(text, 7, " untracked")
    end)

    assert Text.to_string(text) == "tracked untracked"

    # Undo should only remove changes from tracked origin
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == " untracked"
  end

  test "can undo with no origin with text changes, text removed", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    inserted_text = "Hello, world!"
    Text.insert(text, 0, inserted_text)
    assert Text.to_string(text) == inserted_text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "can undo with origin and transaction with text changes, text removed", %{
    doc: doc,
    text: text
  } do
    {:ok, undo_manager} = UndoManager.new(doc, text)
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
    {:ok, undo_manager} = UndoManager.new(doc, text)
    # Set up our tracked origin so that undo manager is only tracking changes from this origin
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
    {:ok, undo_manager} = UndoManager.new(doc, array)

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
    {:ok, undo_manager} = UndoManager.new(doc, map)

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
    {:ok, undo_manager} = UndoManager.new(doc, array)
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
    assert Array.to_list(array) == [
             "untracked1",
             "untracked2",
             "tracked1",
             "tracked2",
             "untracked3"
           ]

    # After undo, only tracked changes should be removed
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == ["untracked1", "untracked2", "untracked3"]
  end

  test "undo only removes changes from tracked origin for map", %{doc: doc, map: map} do
    {:ok, undo_manager} = UndoManager.new(doc, map)
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

  test "can redo without failure when stack is empty", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    UndoManager.redo(undo_manager)
  end

  test "can redo text changes after undo", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    inserted_text = "Hello, world!"
    Text.insert(text, 0, inserted_text)

    # Verify initial state and undo
    assert Text.to_string(text) == inserted_text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""

    # Verify redo restores the change
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == inserted_text
  end

  test "can redo array changes after undo", %{doc: doc, array: array} do
    {:ok, undo_manager} = UndoManager.new(doc, array)

    # Make some changes
    Array.push(array, "first")
    Array.push(array, "second")

    # Verify initial state
    assert Array.to_list(array) == ["first", "second"]

    # Undo and verify
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == []

    # Redo and verify restoration
    UndoManager.redo(undo_manager)
    assert Array.to_list(array) == ["first", "second"]
  end

  test "can redo map changes after undo", %{doc: doc, map: map} do
    {:ok, undo_manager} = UndoManager.new(doc, map)

    # Make some changes
    Yex.Map.set(map, "key1", "value1")
    Yex.Map.set(map, "key2", "value2")

    # Verify initial state
    assert Yex.Map.to_map(map) == %{"key1" => "value1", "key2" => "value2"}

    # Undo and verify
    UndoManager.undo(undo_manager)
    assert Yex.Map.to_map(map) == %{}

    # Redo and verify restoration
    UndoManager.redo(undo_manager)
    assert Yex.Map.to_map(map) == %{"key1" => "value1", "key2" => "value2"}
  end

  test "redo only affects tracked origin changes", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    tracked_origin = "tracked-origin"
    UndoManager.include_origin(undo_manager, tracked_origin)

    # Make untracked changes
    Doc.transaction(doc, "untracked-origin", fn ->
      Text.insert(text, 0, "Untracked ")
    end)

    # Make tracked changes
    Doc.transaction(doc, tracked_origin, fn ->
      Text.insert(text, 10, "tracked ")
    end)

    # Initial state
    assert Text.to_string(text) == "Untracked tracked "

    # Undo tracked changes
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "Untracked "

    # Redo tracked changes
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Untracked tracked "
  end

  test "works with all types", %{doc: doc, text: text, array: array, map: map} do
    {:ok, text_manager} = UndoManager.new(doc, text)
    {:ok, array_manager} = UndoManager.new(doc, array)
    {:ok, map_manager} = UndoManager.new(doc, map)

    # Test with text
    Text.insert(text, 0, "Hello")
    assert Text.to_string(text) == "Hello"
    UndoManager.undo(text_manager)
    assert Text.to_string(text) == ""
    UndoManager.redo(text_manager)
    assert Text.to_string(text) == "Hello"

    # Test with array
    Array.push(array, "item")
    assert Array.to_list(array) == ["item"]
    UndoManager.undo(array_manager)
    assert Array.to_list(array) == []
    UndoManager.redo(array_manager)
    assert Array.to_list(array) == ["item"]

    # Test with map
    Yex.Map.set(map, "key", "value")
    assert Yex.Map.to_map(map) == %{"key" => "value"}
    UndoManager.undo(map_manager)
    assert Yex.Map.to_map(map) == %{}
    UndoManager.redo(map_manager)
    assert Yex.Map.to_map(map) == %{"key" => "value"}
  end

  test "can expand scope to include additional text", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    additional_text = Doc.get_text(doc, "additional_text")

    # Add text to both shared types
    Text.insert(text, 0, "Original")
    Text.insert(additional_text, 0, "Additional")

    # Initially, undo only affects original text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
    assert Text.to_string(additional_text) == "Additional"

    # Expand scope to include additional text
    UndoManager.expand_scope(undo_manager, additional_text)

    # New changes should affect both
    Text.insert(text, 0, "New Original")
    Text.insert(additional_text, 0, "New Additional")

    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
    assert Text.to_string(additional_text) == "Additional"
  end

  test "can expand scope to include multiple types", %{
    doc: doc,
    text: text,
    array: array,
    map: map
  } do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Expand scope to include array and map
    UndoManager.expand_scope(undo_manager, array)
    UndoManager.expand_scope(undo_manager, map)

    # Make changes to all types
    Text.insert(text, 0, "Text")
    Array.push(array, "Array")
    Yex.Map.set(map, "key", "Map")

    # Verify initial state
    assert Text.to_string(text) == "Text"
    assert Array.to_list(array) == ["Array"]
    assert Yex.Map.to_map(map) == %{"key" => "Map"}

    # Undo should affect all types
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
    assert Array.to_list(array) == []
    assert Yex.Map.to_map(map) == %{}
  end

  test "can exclude an origin from tracking", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    origin = "test-origin"
    UndoManager.exclude_origin(undo_manager, origin)
  end

  test "excluded origin changes are not tracked", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    excluded_origin = "excluded-origin"
    UndoManager.exclude_origin(undo_manager, excluded_origin)

    # Make changes with excluded origin
    Doc.transaction(doc, excluded_origin, fn ->
      Text.insert(text, 0, "Excluded ")
    end)

    # Make changes with unspecified origin
    Text.insert(text, 9, "tracked ")

    # Make changes with excluded origin
    Doc.transaction(doc, excluded_origin, fn ->
      Text.insert(text, 17, "Also Excluded")
    end)

    # Initial state should have all changes
    assert Text.to_string(text) == "Excluded tracked Also Excluded"

    # After undo, only non-excluded changes should be removed
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "Excluded Also Excluded"
  end

  test "stop_capturing prevents merging of changes", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # prove changes are merging
    Text.insert(text, 0, "a")
    Text.insert(text, 1, "b")
    assert Text.to_string(text) == "ab"
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""

    # do it again with stop capture
    Text.insert(text, 0, "a")
    # Stop capturing to prevent merging
    UndoManager.stop_capturing(undo_manager)

    # Second change
    Text.insert(text, 1, "b")

    # Initial state should have both changes
    assert Text.to_string(text) == "ab"

    # Undo should only remove the second change
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "a"
  end

  test "changes merge without stop_capturing", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Make two changes in quick succession
    Text.insert(text, 0, "a")
    Text.insert(text, 1, "b")

    # Initial state should have both changes
    assert Text.to_string(text) == "ab"

    # Undo should remove both changes since they were merged
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "stop_capturing works with different types", %{doc: doc, array: array} do
    {:ok, undo_manager} = UndoManager.new(doc, array)

    # First change
    Array.push(array, "first")

    # Stop capturing to prevent merging
    UndoManager.stop_capturing(undo_manager)

    # Second change
    Array.push(array, "second")

    # Initial state should have both items
    assert Array.to_list(array) == ["first", "second"]

    # Undo should only remove the second item
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == ["first"]
  end

  test "clear removes all stack items", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Make some changes that will create undo stack items
    Text.insert(text, 0, "Hello")
    Text.insert(text, 5, " World")
    assert Text.to_string(text) == "Hello World"

    # Clear the undo manager
    UndoManager.clear(undo_manager)

    # Try to undo - should have no effect since stack was cleared
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "Hello World"

    # Try to redo - should have no effect since stack was cleared
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Hello World"
  end

  test "can create an undo manager with options", %{doc: doc, text: text} do
    options = %UndoManager.Options{capture_timeout: 1000}
    {:ok, undo_manager} = UndoManager.new_with_options(doc, text, options)
    assert %UndoManager{} = undo_manager
    assert is_reference(undo_manager.reference)
  end

  test "capture timeout works as expected", %{doc: doc, text: text} do
    options = %UndoManager.Options{capture_timeout: 100}
    {:ok, undo_manager} = UndoManager.new_with_options(doc, text, options)

    Text.insert(text, 0, "a")

    # se are testing Undo manager's ability to batch after timeout, 150ms should create two batches
    Process.sleep(150)
    Text.insert(text, 1, "b")

    UndoManager.undo(undo_manager)
    # 'a' still remains due to timeout
    assert Text.to_string(text) == "a"
  end

  test "demonstrates constructor with options", %{doc: doc, text: text} do
    options = %UndoManager.Options{capture_timeout: 100}
    {:ok, undo_manager} = UndoManager.new_with_options(doc, text, options)
    # prove tests are batched
    Text.insert(text, 0, "a")
    Text.insert(text, 1, "b")
    assert Text.to_string(text) == "ab"

    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""

    # Prove options are respected
    Text.insert(text, 0, "c")

    # sleep longer than capture_timeout to ensure two batches are created
    Process.sleep(150)
    Text.insert(text, 1, "d")
    assert Text.to_string(text) == "cd"

    UndoManager.undo(undo_manager)

    # 'c' still remains due to timeout
    assert Text.to_string(text) == "c"
    UndoManager.undo(undo_manager)
    # get back to empty
    assert Text.to_string(text) == ""

    # Prove option means insufficient timeout will still batch
    Text.insert(text, 0, "e")

    # undo manager has a timeout of 100ms, so this sleep of 50ms should ...
    # ... be insufficient and will allow the changes to be in one batch
    Process.sleep(50)
    Text.insert(text, 1, "f")
    assert Text.to_string(text) == "ef"

    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "basic constructor example", %{doc: doc, text: text} do
    # From docs: const undoManager = new Y.UndoManager(ytext)
    {:ok, undo_manager} = UndoManager.new(doc, text)
    assert %UndoManager{} = undo_manager
    assert is_reference(undo_manager.reference)
  end

  test "demonstrates exact stopCapturing behavior from docs", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Example from docs:
    # // without stopCapturing
    Text.insert(text, 0, "a")
    Text.insert(text, 1, "b")
    UndoManager.undo(undo_manager)
    # note that 'ab' was removed
    assert Text.to_string(text) == ""

    # Reset state
    Text.delete(text, 0, Text.length(text))

    # Example from docs:
    # // with stopCapturing
    Text.insert(text, 0, "a")
    # Ensure subsequent changes are captured separately
    UndoManager.stop_capturing(undo_manager)
    Text.insert(text, 1, "b")
    UndoManager.undo(undo_manager)
    # note that only 'b' was removed
    assert Text.to_string(text) == "a"
  end

  test "demonstrates tracking specific origins from docs", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # From docs: undoManager.addToScope(ytext)
    UndoManager.include_origin(undo_manager, "my-origin")

    # Make changes with tracked origin
    Doc.transaction(doc, "my-origin", fn ->
      Text.insert(text, 0, "tracked changes")
    end)

    # Make changes with untracked origin
    Doc.transaction(doc, "other-origin", fn ->
      Text.insert(text, 0, "untracked ")
    end)

    assert Text.to_string(text) == "untracked tracked changes"

    # Undo should only affect tracked changes
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "untracked "
  end

  test "demonstrates clear functionality from docs", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Make some changes
    Text.insert(text, 0, "hello")
    Text.insert(text, 5, " world")
    assert Text.to_string(text) == "hello world"

    # From docs: undoManager.clear()
    UndoManager.clear(undo_manager)

    # Verify undo/redo have no effect after clear
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "hello world"
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "hello world"
  end

  test "demonstrates scope expansion from docs", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    additional_text = Doc.get_text(doc, "additional_text")

    # From docs: undoManager.addToScope(additionalYText)
    UndoManager.expand_scope(undo_manager, additional_text)

    # Make changes to both texts
    Text.insert(text, 0, "first text")
    Text.insert(additional_text, 0, "second text")

    # Undo should affect both texts
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
    assert Text.to_string(additional_text) == ""
  end

  defmodule CustomBinding do
    # Just a marker module to match the JavaScript example
  end

  test "demonstrates tracked origins specification from docs", %{doc: doc, text: text} do
    # Mirror the docs setup:
    # const undoManager = new Y.UndoManager(ytext, {
    #   trackedOrigins: new Set([42, CustomBinding])
    # })
    {:ok, undo_manager} = UndoManager.new(doc, text)
    UndoManager.include_origin(undo_manager, 42)
    UndoManager.include_origin(undo_manager, CustomBinding)

    # First example: untracked origin (null)
    Text.insert(text, 0, "abc")
    UndoManager.undo(undo_manager)
    # not tracked because origin is null
    assert Text.to_string(text) == "abc"
    # revert change
    Text.delete(text, 0, 3)

    # Second example: tracked origin (42)
    Doc.transaction(doc, 42, fn ->
      Text.insert(text, 0, "abc")
    end)

    UndoManager.undo(undo_manager)
    # tracked because origin is 42
    assert Text.to_string(text) == ""

    # Third example: untracked origin (41)
    Doc.transaction(doc, 41, fn ->
      Text.insert(text, 0, "abc")
    end)

    UndoManager.undo(undo_manager)
    # not tracked because 41 isn't in tracked origins
    assert Text.to_string(text) == "abc"
    # revert change
    Text.delete(text, 0, 3)

    # Fourth example: tracked origin (CustomBinding)
    Doc.transaction(doc, CustomBinding, fn ->
      Text.insert(text, 0, "abc")
    end)

    UndoManager.undo(undo_manager)
    # tracked because CustomBinding is in tracked origins
    assert Text.to_string(text) == ""
  end

  test "multiple undo/redo sequences work correctly", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # First change
    Text.insert(text, 0, "Hello")

    # stop tracking to ensure changes are not batched
    UndoManager.stop_capturing(undo_manager)

    # Second change
    Text.insert(text, 5, " World")
    assert Text.to_string(text) == "Hello World"

    # First undo
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "Hello"

    # First redo
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Hello World"

    # Undo both changes
    UndoManager.undo(undo_manager)
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""

    # Redo both changes
    UndoManager.redo(undo_manager)
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Hello World"
  end

  test "redo stack is cleared when new changes are made", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)

    # Initial change
    Text.insert(text, 0, "Hello")

    # Undo the change
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""

    # Make a new change instead of redo
    Text.insert(text, 0, "Different")

    # Try to redo - should have no effect since we made a new change
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Different"
  end

  test "redo with multiple types in scope", %{doc: doc, text: text, array: array} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    UndoManager.expand_scope(undo_manager, array)

    # Make changes to both types
    Text.insert(text, 0, "Hello")
    Array.push(array, "World")

    # Verify initial state
    assert Text.to_string(text) == "Hello"
    assert Array.to_list(array) == ["World"]

    # Undo changes to both types
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
    assert Array.to_list(array) == []

    # Redo should restore both changes
    UndoManager.redo(undo_manager)
    assert Text.to_string(text) == "Hello"
    assert Array.to_list(array) == ["World"]
  end

  test "new_with_options unwraps successful results", %{
    doc: doc,
    text: text,
    array: array,
    map: map
  } do
    options = %UndoManager.Options{capture_timeout: 1000}

    # Test Text type
    {:ok, text_manager} = UndoManager.new_with_options(doc, text, options)
    assert match?(%UndoManager{}, text_manager)
    assert is_reference(text_manager.reference)

    # Test Array type
    {:ok, array_manager} = UndoManager.new_with_options(doc, array, options)
    assert match?(%UndoManager{}, array_manager)
    assert is_reference(array_manager.reference)

    # Test Map type
    {:ok, map_manager} = UndoManager.new_with_options(doc, map, options)
    assert match?(%UndoManager{}, map_manager)
    assert is_reference(map_manager.reference)
  end

  test "undo works with embedded Yex objects", %{doc: doc} do
    # Create an array to hold our embedded text
    array = Doc.get_array(doc, "array")
    {:ok, undo_manager} = UndoManager.new(doc, array)

    # Create a text object with initial content
    text_prelim = TextPrelim.from("Initial")

    # Push the text into the array
    Array.push(array, text_prelim)

    # Fetch the text from the array and verify initial content
    {:ok, embedded_text} = Array.fetch(array, 0)
    assert Text.to_string(embedded_text) == "Initial"

    # Stop capturing to prevent merging the push and insert operations
    UndoManager.stop_capturing(undo_manager)

    # Insert additional text
    Text.insert(embedded_text, 7, " Content")
    assert Text.to_string(embedded_text) == "Initial Content"

    # Undo should revert the inserted text but keep the preliminary text
    UndoManager.undo(undo_manager)
    assert Text.to_string(embedded_text) == "Initial"
  end

  test "can undo xml fragment changes", %{doc: doc, xml_fragment: xml_fragment} do
    {:ok, undo_manager} = UndoManager.new(doc, xml_fragment)

    # Add some XML content
    XmlFragment.push(xml_fragment, XmlTextPrelim.from("Hello"))
    XmlFragment.push(xml_fragment, XmlElementPrelim.empty("div"))

    # Verify initial state
    assert XmlFragment.to_string(xml_fragment) == "Hello<div></div>"

    # Undo changes
    UndoManager.undo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == ""
  end

  test "can undo xml element changes", %{doc: doc, xml_fragment: xml_fragment} do
    # First create an element in the fragment
    XmlFragment.push(xml_fragment, XmlElementPrelim.empty("div"))
    {:ok, element} = XmlFragment.fetch(xml_fragment, 0)

    {:ok, undo_manager} = UndoManager.new(doc, element)

    # Add attributes and content
    XmlElement.insert_attribute(element, "class", "test")
    XmlElement.push(element, XmlTextPrelim.from("content"))

    # Verify initial state
    assert XmlElement.to_string(element) == "<div class=\"test\">content</div>"

    # Undo changes
    UndoManager.undo(undo_manager)
    assert XmlElement.to_string(element) == "<div></div>"
  end

  test "can undo xml text changes", %{doc: doc, xml_fragment: xml_fragment} do
    # First create a text node in the fragment
    XmlFragment.push(xml_fragment, XmlTextPrelim.from(""))
    {:ok, text_node} = XmlFragment.fetch(xml_fragment, 0)

    {:ok, undo_manager} = UndoManager.new(doc, text_node)

    # Add content and formatting
    XmlText.insert(text_node, 0, "Hello World")
    XmlText.format(text_node, 0, 5, %{"bold" => true})

    # Verify initial state
    assert XmlText.to_string(text_node) == "<bold>Hello</bold> World"

    # Undo changes
    UndoManager.undo(undo_manager)
    assert XmlText.to_string(text_node) == ""
  end

  test "undo only removes changes from tracked origin for xml", %{
    doc: doc,
    xml_fragment: xml_fragment
  } do
    {:ok, undo_manager} = UndoManager.new(doc, xml_fragment)
    tracked_origin = "tracked-origin"
    UndoManager.include_origin(undo_manager, tracked_origin)

    # Make untracked changes
    Doc.transaction(doc, "untracked-origin", fn ->
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("untracked"))
    end)

    # Make tracked changes
    Doc.transaction(doc, tracked_origin, fn ->
      XmlFragment.push(xml_fragment, XmlElementPrelim.empty("div"))
    end)

    # Make more untracked changes
    Doc.transaction(doc, "untracked-origin", fn ->
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("more-untracked"))
    end)

    # Verify initial state
    assert XmlFragment.to_string(xml_fragment) == "untracked<div></div>more-untracked"

    # Undo should only remove tracked changes
    UndoManager.undo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == "untrackedmore-untracked"
  end

  test "can redo xml changes", %{doc: doc, xml_fragment: xml_fragment} do
    {:ok, undo_manager} = UndoManager.new(doc, xml_fragment)

    # Make some changes
    XmlFragment.push(xml_fragment, XmlTextPrelim.from("Hello"))
    XmlFragment.push(xml_fragment, XmlElementPrelim.empty("div"))

    # Verify initial state
    assert XmlFragment.to_string(xml_fragment) == "Hello<div></div>"

    # Undo changes
    UndoManager.undo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == ""

    # Redo changes
    UndoManager.redo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == "Hello<div></div>"
  end

  test "works with nested xml structure", %{doc: doc, xml_fragment: xml_fragment} do
    {:ok, undo_manager} = UndoManager.new(doc, xml_fragment)

    # Create a nested structure
    XmlFragment.push(
      xml_fragment,
      XmlElementPrelim.new("div", [
        XmlElementPrelim.new("span", [
          XmlTextPrelim.from("nested content")
        ])
      ])
    )

    # Verify initial state
    assert XmlFragment.to_string(xml_fragment) == "<div><span>nested content</span></div>"

    # Undo should remove entire structure
    UndoManager.undo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == ""

    # Redo should restore entire structure
    UndoManager.redo(undo_manager)
    assert XmlFragment.to_string(xml_fragment) == "<div><span>nested content</span></div>"
  end

  test "returns error when trying to create undo manager with invalid document", %{text: text} do
    invalid_doc = %{not: "a valid doc"}

    assert_raise ArgumentError, fn ->
      UndoManager.new(invalid_doc, text)
    end
  end

  test "guards prevent invalid scope in new/2" do
    doc = Doc.new()
    invalid_scope = %{not: "a valid scope"}

    assert_raise FunctionClauseError, fn ->
      UndoManager.new(doc, invalid_scope)
    end
  end

  test "guards prevent invalid scope in new_with_options/3" do
    doc = Doc.new()
    invalid_scope = %{not: "a valid scope"}
    options = %UndoManager.Options{capture_timeout: 1000}

    assert_raise FunctionClauseError, fn ->
      UndoManager.new_with_options(doc, invalid_scope, options)
    end
  end

  test "guards allow valid scope types", %{doc: doc} do
    # Test each valid scope type
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")
    xml_fragment = Doc.get_xml_fragment(doc, "xml_fragment")

    # All of these should work without raising
    {:ok, _} = UndoManager.new(doc, text)
    {:ok, _} = UndoManager.new(doc, array)
    {:ok, _} = UndoManager.new(doc, map)
    {:ok, _} = UndoManager.new(doc, xml_fragment)
  end

  test "guards allow valid scope types with options", %{doc: doc} do
    # Test each valid scope type
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")
    xml_fragment = Doc.get_xml_fragment(doc, "xml_fragment")
    options = %UndoManager.Options{capture_timeout: 1000}

    # All of these should work without raising
    {:ok, _} = UndoManager.new_with_options(doc, text, options)
    {:ok, _} = UndoManager.new_with_options(doc, array, options)
    {:ok, _} = UndoManager.new_with_options(doc, map, options)
    {:ok, _} = UndoManager.new_with_options(doc, xml_fragment, options)
  end

  test "scope validation works correctly", %{doc: doc} do
    # Test valid scopes
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")
    xml_fragment = Doc.get_xml_fragment(doc, "xml_fragment")

    # These should all return {:ok, _} results
    assert {:ok, _} = UndoManager.new(doc, text)
    assert {:ok, _} = UndoManager.new(doc, array)
    assert {:ok, _} = UndoManager.new(doc, map)
    assert {:ok, _} = UndoManager.new(doc, xml_fragment)

    # Test invalid scopes
    invalid_scope = %{not: "a valid scope"}

    assert_raise FunctionClauseError, fn ->
      UndoManager.new(doc, invalid_scope)
    end

    assert_raise FunctionClauseError, fn ->
      UndoManager.new(doc, nil)
    end

    assert_raise FunctionClauseError, fn ->
      UndoManager.new(doc, "string")
    end

    assert_raise FunctionClauseError, fn ->
      UndoManager.new(doc, 123)
    end
  end

  test "defguard is_valid_scope can be imported and used" do
    import Yex.UndoManager, only: [is_valid_scope: 1]
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    invalid_scope = %{not: "a valid scope"}

    # Test valid scope
    assert is_valid_scope(text)

    # Test invalid scope
    refute is_valid_scope(invalid_scope)
    refute is_valid_scope(nil)
    refute is_valid_scope("string")
    refute is_valid_scope(123)
  end

  test "new_with_options handles NIF errors", %{doc: doc, text: text} do
    # Invalid timeout to trigger error
    options = %UndoManager.Options{capture_timeout: -1}

    # Mock the NIF call to return an error
    with_mock Yex.Nif,
      undo_manager_new_with_options: fn _doc, _scope, _options ->
        {:error, "test error message"}
      end do
      assert {:error, "NIF error: test error message"} =
               UndoManager.new_with_options(doc, text, options)
    end
  end

  test "can observe undo stack items with metadata", %{doc: doc, text: text} do
    {:ok, manager} = UndoManager.new(doc, text)
    test_pid = self()

    UndoManager.on_item_added(manager, fn event ->
      send(test_pid, {:item_added, event})
    end)

    # Make first change
    Doc.transaction(doc, "origin-1", fn ->
      Text.insert(text, 0, "Hello")
    end)

    # Verify event was received
    assert_receive {:item_added, event}
    assert event.origin == "origin-1"
    assert event.kind == :text
    assert is_map(event.delta)

    # Stop capturing to ensure separate events
    UndoManager.stop_capturing(manager)

    # Make second change with different origin
    Doc.transaction(doc, "origin-2", fn ->
      Text.insert(text, 5, " World")
    end)

    # Verify second event
    assert_receive {:item_added, event}
    assert event.origin == "origin-2"
    assert event.kind == :text
    assert is_map(event.delta)

    # Verify text content
    assert Text.to_string(text) == "Hello World"
  end

  test "metadata is cleaned up when undo manager is cleared", %{doc: doc, text: text} do
    {:ok, manager} = UndoManager.new(doc, text)
    test_pid = self()

    UndoManager.on_item_added(manager, fn event ->
      send(test_pid, {:item_added, event})
    end)

    # Make multiple changes with different origins
    Doc.transaction(doc, "origin-1", fn ->
      Text.insert(text, 0, "Hello")
    end)

    assert_receive {:item_added, event}
    assert event.origin == "origin-1"
    assert event.kind == :text
    assert is_map(event.delta)

    Doc.transaction(doc, "origin-2", fn ->
      Text.insert(text, 5, " World")
    end)

    assert_receive {:item_added, event}
    assert event.origin == "origin-2"
    assert event.kind == :text
    assert is_map(event.delta)

    # Clear the undo manager
    {:ok, _} = UndoManager.clear(manager)

    # Make another change to verify no more events are received
    Text.insert(text, 11, "!")
    refute_receive {:item_added, _}
  end

  test "observer callbacks receive correct event data", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    test_pid = self()

    UndoManager.on_item_added(undo_manager, fn event ->
      send(test_pid, {:added, event})
    end)

    UndoManager.on_item_popped(undo_manager, fn event ->
      send(test_pid, {:popped, event})
    end)

    # Make changes with specific origin
    Doc.transaction(doc, "test-origin", fn ->
      Text.insert(text, 0, "Hello")
    end)

    # Verify added event
    assert_receive {:added, event}
    assert event.kind == :text
    assert event.origin == "test-origin"
    # The exact structure depends on yrs
    assert is_map(event.delta)

    # Undo and verify popped event
    UndoManager.undo(undo_manager)
    assert_receive {:popped, event}
    assert event.kind == :text
    assert event.origin == "test-origin"
    assert is_map(event.delta)
  end

  test "can have multiple observers for the same event type", %{doc: doc, text: text} do
    {:ok, manager} = UndoManager.new(doc, text)
    test_pid = self()

    # Register two callbacks for the same event
    UndoManager.on_item_added(manager, fn event ->
      send(test_pid, {:observer1, event})
    end)

    UndoManager.on_item_added(manager, fn event ->
      send(test_pid, {:observer2, event})
    end)

    # Make a change with specific origin
    Doc.transaction(doc, "test-origin", fn ->
      Text.insert(text, 0, "Hello")
    end)

    # Verify both callbacks received the event
    assert_receive {:observer1, event1}
    assert_receive {:observer2, event2}
    assert event1.origin == "test-origin"
    assert event2.origin == "test-origin"
    assert event1.kind == :text
    assert event2.kind == :text
  end

  test "events contain correct data for different types", %{doc: doc, text: text, array: array} do
    {:ok, text_manager} = UndoManager.new(doc, text)
    {:ok, array_manager} = UndoManager.new(doc, array)
    test_pid = self()

    UndoManager.on_item_added(text_manager, fn event ->
      send(test_pid, {:added, event})
    end)

    UndoManager.on_item_added(array_manager, fn event ->
      send(test_pid, {:added, event})
    end)

    # Test text changes
    Doc.transaction(doc, "text-origin", fn ->
      Text.insert(text, 0, "Hello")
    end)

    assert_receive {:added, text_event}
    assert text_event.kind == :text
    assert text_event.origin == "text-origin"
    assert is_map(text_event.delta)

    # Test array changes
    Doc.transaction(doc, "array-origin", fn ->
      Array.push(array, "World")
    end)

    assert_receive {:added, array_event}
    assert array_event.kind == :array
    assert array_event.origin == "array-origin"
    assert is_map(array_event.delta)
  end

  test "can observe item updates", %{doc: doc, text: text} do
    {:ok, undo_manager} = UndoManager.new(doc, text)
    test_pid = self()

    UndoManager.on_item_updated(undo_manager, fn event ->
      send(test_pid, {:updated, event})
    end)

    # Make changes within capture timeout
    Text.insert(text, 0, "Hello")
    Text.insert(text, 5, " World")

    # Verify update event
    assert_receive {:updated, event}
    assert event.kind == :text
    assert is_map(event.delta)

    # Stop capturing to create a new stack item
    UndoManager.stop_capturing(undo_manager)

    # Make more changes
    Text.insert(text, 11, "!")

    # No update event should be received since we stopped capturing
    refute_receive {:updated, _event}
  end
end
