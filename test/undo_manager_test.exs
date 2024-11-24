defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, UndoManager}
  doctest Yex.UndoManager

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    undo_manager = UndoManager.new(doc, text)

    # Return these as the test context
    {:ok, doc: doc, text: text, undo_manager: undo_manager}
  end

  test "can create an undo manager", %{undo_manager: undo_manager} do
    assert %UndoManager{} = undo_manager
    assert undo_manager.reference != nil
  end

  test "can undo without failure when stack is empty", %{undo_manager: undo_manager} do
    UndoManager.undo(undo_manager)
  end

  test "can include an origin for tracking", %{undo_manager: undo_manager} do
    origin = "test-origin"
    UndoManager.include_origin(undo_manager, origin)
  end

  test "can undo with no origin with text changes, text removed", %{text: text, undo_manager: undo_manager} do
    inserted_text = "Hello, world!"
    Text.insert(text, 0, inserted_text)
    assert Text.to_string(text) == inserted_text
    UndoManager.undo(undo_manager)
    assert Text.to_string(text) == ""
  end

  test "can undo with origin and transaction with text changes, text removed", %{doc: doc, text: text, undo_manager: undo_manager} do
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

  test "undo only removes changes from tracked origin", %{doc: doc, text: text, undo_manager: undo_manager} do
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

end
