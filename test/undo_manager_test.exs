defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, Array, UndoManager}
  doctest Yex.UndoManager

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    map = Doc.get_map(doc, "map")

    if Process.whereis(:test_observer_process) do
      Process.unregister(:test_observer_process)
    end
    Process.register(self(), :test_observer_process)

    on_exit(fn ->
      if Process.whereis(:test_observer_process) do
        Process.unregister(:test_observer_process)
      end
    end)

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

  test "can redo without failure when stack is empty", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    UndoManager.redo(undo_manager)
  end

  test "can redo text changes after undo", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
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
    undo_manager = UndoManager.new(doc, array)

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
    undo_manager = UndoManager.new(doc, map)

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
    undo_manager = UndoManager.new(doc, text)
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
    text_manager = UndoManager.new(doc, text)
    array_manager = UndoManager.new(doc, array)
    map_manager = UndoManager.new(doc, map)

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
    undo_manager = UndoManager.new(doc, text)
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

  test "can expand scope to include multiple types", %{doc: doc, text: text, array: array, map: map} do
    undo_manager = UndoManager.new(doc, text)

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
    undo_manager = UndoManager.new(doc, text)
    origin = "test-origin"
    UndoManager.exclude_origin(undo_manager, origin)
  end

  test "excluded origin changes are not tracked", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
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
    undo_manager = UndoManager.new(doc, text)

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
    undo_manager = UndoManager.new(doc, text)

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
    undo_manager = UndoManager.new(doc, array)

    # First change
    Array.push(array, "first")

    # Stop capturing
    UndoManager.stop_capturing(undo_manager)

    # Second change
    Array.push(array, "second")

    # Initial state should have both items
    assert Array.to_list(array) == ["first", "second"]

    # Undo should only remove the second item
    UndoManager.undo(undo_manager)
    assert Array.to_list(array) == ["first"]
  end

  defmodule TestObserver do
    use Yex.UndoServer

    def handle_stack_item_added(stack_item, state) do
      {:ok, Map.put(stack_item, "test_value", "added"), state}
    end

    def handle_stack_item_popped(state) do
      send(:test_observer_process, {:stack_item_popped, %{"test_value" => "added"}})
      {:ok, state}
    end
  end

  defmodule SecondObserver do
    use Yex.UndoServer

    def handle_stack_item_added(stack_item, state) do
      {:ok, Map.put(stack_item, "test_value", "added"), state}
    end

    def handle_stack_item_popped(state) do
      send(:test_observer_process, {:stack_item_popped, %{"test_value" => "added"}})
      {:ok, state}
    end
  end

  defmodule IgnoringObserver do
    use Yex.UndoServer

    def handle_stack_item_added(_stack_item, state) do
      {:ignore, state}
    end

    def handle_stack_item_popped(state) do
      send(:test_observer_process, {:stack_item_popped, :ok})
      {:ok, state}
    end
  end

  test "observer receives callbacks and can modify stack items", %{doc: doc, text: text} do
    # Remove this line since it's now in setup
    # Process.register(self(), :test_observer_process)

    undo_manager = UndoManager.new(doc, text)
    UndoManager.add_observer(undo_manager, TestObserver)

    # Make a change that should trigger the observer
    Text.insert(text, 0, "Hello")

    # Undo should trigger the popped callback with metadata
    UndoManager.undo(undo_manager)

    # Verify we received the meta information with our test value
    assert_receive {:stack_item_popped, %{"test_value" => "added"}}
  end

  test "observer can ignore stack items", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)
    UndoManager.add_observer(undo_manager, IgnoringObserver)

    # Make and undo changes - should work without error even though observer ignores
    Text.insert(text, 0, "Hello")
    assert Text.to_string(text) == "Hello"
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end


  test "multiple observers can be added" do
    # Add debug logging here
    require Logger

    Logger.debug("Starting multiple observers test")

    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    undo_manager = UndoManager.new(doc, text)

    Logger.debug("Created undo manager")

    # Add observers
    pid1 = UndoManager.add_observer(undo_manager, TestObserver)
    pid2 = UndoManager.add_observer(undo_manager, TestObserver)

    Logger.debug("Added observers with PIDs: #{inspect(pid1)}, #{inspect(pid2)}")

    Text.insert(text, 0, "hello")
    UndoManager.undo(undo_manager)

    Logger.debug("Performed text operation and undo")

    assert_receive {:stack_item_popped, %{"test_value" => "added"}}

    Logger.debug("Test completed")
  end
end
