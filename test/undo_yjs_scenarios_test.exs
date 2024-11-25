defmodule Yex.UndoYjsScenariosTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, UndoManager}

  # Add TestObserver module definition
  defmodule TestObserver do
    use Yex.UndoServer

    def handle_stack_item_added(stack_item, state) do
      stack_item = Map.put(stack_item, "test_value", "added")
      {:ok, stack_item, state}
    end

    def handle_stack_item_popped(state) do
      send(:test_observer_process, {:stack_item_popped, %{"test_value" => "added"}})
      {:ok, state}
    end
  end

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")

    # Add process registration to setup
    if Process.whereis(:test_observer_process) do
      Process.unregister(:test_observer_process)
    end
    Process.register(self(), :test_observer_process)

    on_exit(fn ->
      if Process.whereis(:test_observer_process) do
        Process.unregister(:test_observer_process)
      end
    end)

    {:ok, doc: doc, text: text}
  end

  test "basic constructor example", %{doc: doc, text: text} do
    # From docs: const undoManager = new Y.UndoManager(ytext)
    undo_manager = UndoManager.new(doc, text)
    assert %UndoManager{} = undo_manager
  end

  test "demonstrates exact stopCapturing behavior from docs", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)

    # Example from docs:
    # // without stopCapturing
    Text.insert(text, 0, "a")
    Text.insert(text, 1, "b")
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "" # note that 'ab' was removed

    # Reset state
    Text.delete(text, 0, Text.length(text))

    # Example from docs:
    # // with stopCapturing
    Text.insert(text, 0, "a")
    UndoManager.stop_capturing(undo_manager)
    Text.insert(text, 1, "b")
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "a" # note that only 'b' was removed
  end

  test "demonstrates tracking specific origins from docs", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)

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
    undo_manager = UndoManager.new(doc, text)

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
    undo_manager = UndoManager.new(doc, text)
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

  test "demonstrates observer pattern from docs", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)

    # From docs: undoManager.on('stack-item-added', event => { ... })
    UndoManager.add_observer(undo_manager, TestObserver)

    Text.insert(text, 0, "hello")
    UndoManager.undo(undo_manager)

    # Observer callback should have been triggered
    assert_receive {:stack_item_popped, %{"test_value" => "added"}}
  end

  defmodule CustomBinding do
    # Just a marker module to match the JavaScript example
  end

  test "demonstrates tracked origins specification from docs", %{doc: doc, text: text} do
    # Mirror the docs setup:
    # const undoManager = new Y.UndoManager(ytext, {
    #   trackedOrigins: new Set([42, CustomBinding])
    # })
    undo_manager = UndoManager.new(doc, text)
    UndoManager.include_origin(undo_manager, 42)
    UndoManager.include_origin(undo_manager, CustomBinding)

    # First example: untracked origin (null)
    Text.insert(text, 0, "abc")
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "abc" # not tracked because origin is null
    Text.delete(text, 0, 3) # revert change

    # Second example: tracked origin (42)
    Doc.transaction(doc, 42, fn ->
      Text.insert(text, 0, "abc")
    end)
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "" # tracked because origin is 42

    # Third example: untracked origin (41)
    Doc.transaction(doc, 41, fn ->
      Text.insert(text, 0, "abc")
    end)
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "abc" # not tracked because 41 isn't in tracked origins
    Text.delete(text, 0, 3) # revert change

    # Fourth example: tracked origin (CustomBinding)
    Doc.transaction(doc, CustomBinding, fn ->
      Text.insert(text, 0, "abc")
    end)
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == "" # tracked because CustomBinding is in tracked origins
  end


end
