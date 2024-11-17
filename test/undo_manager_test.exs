defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, UndoManager}
  doctest Yex.UndoManager

  test "can create an undo manager" do
    doc = Doc.new()
    undo_manager = UndoManager.new(doc)

    assert %UndoManager{} = undo_manager
    assert undo_manager.reference != nil
  end

  test "can include an origin for tracking" do
    doc = Doc.new()
    undo_manager = UndoManager.new(doc)

    origin = "test-origin"
    UndoManager.include_origin(undo_manager, origin)
  end

  test "can undo without failure when stack is empty" do
    doc = Doc.new()
    undo_manager = UndoManager.new(doc)

    UndoManager.undo(undo_manager)
  end

  test "can undo text changes from tracked origin" do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    undo_manager = UndoManager.new(doc)
    origin = "test-origin"

    # Include our origin for tracking
    UndoManager.include_origin(undo_manager, origin)

    # Make changes within a transaction with our tracked origin
    Doc.transaction(doc, origin, fn ->
      Text.insert(text, 0, "Hello World")
    end)

    # Verify text was changed
    assert Text.to_string(text) == "Hello World"

    # Undo the change and check if it was successful
    assert UndoManager.undo(undo_manager) == true

    # Verify text was reverted
    assert Text.to_string(text) == ""
  end

  test "attempts to undo direct changes without transaction" do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    undo_manager = UndoManager.new(doc)

    # Try to make changes directly
    Text.insert(text, 0, "Hello World")

    # Verify text was changed
    assert Text.to_string(text) == "Hello World"

    # Try to undo the change
    UndoManager.undo(undo_manager)

    # Check if the text was affected
    assert Text.to_string(text) == "Hello World" # We expect this to stay unchanged
  end
end
