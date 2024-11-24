defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, UndoManager}
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

  # test "can include an origin for tracking", %{undo_manager: undo_manager} do
  #   origin = "test-origin"
  #   UndoManager.include_origin(undo_manager, origin)
  # end

  # test "can undo text changes from tracked origin", %{doc: doc, text: text, undo_manager: undo_manager} do
  #   origin = "test-origin"
  #   ...
  # end

  # test "attempts to undo direct changes without transaction", %{text: text, undo_manager: undo_manager} do
  #   ...
  # end
end
