defmodule Yex.UndoServerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, UndoManager}
  doctest Yex.UndoManager

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
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
    {:ok, doc: doc, text: text, map: map}
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

  test "multiple observers can be added", %{doc: doc, text: text} do
    undo_manager = UndoManager.new(doc, text)

    # Add observers - prefix with underscore since we don't use the return values
    _pid1 = UndoManager.add_observer(undo_manager, TestObserver)
    _pid2 = UndoManager.add_observer(undo_manager, TestObserver)

    Text.insert(text, 0, "hello")
    UndoManager.undo(undo_manager)

    assert_receive {:stack_item_popped, %{"test_value" => "added"}}
  end
end
