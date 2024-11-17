defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  doctest Yex.UndoManager

  test "can create an undo manager" do
    doc = Yex.Doc.new()
    undo_manager = Yex.Nif.undo_manager_new(doc)

    assert %Yex.UndoManager{} = undo_manager
    assert undo_manager.reference != nil
  end

  test "can include an origin for tracking" do
    doc = Yex.Doc.new()
    undo_manager = Yex.Nif.undo_manager_new(doc)

    # Create a simple binary origin
    origin = "test-origin"
    Yex.Nif.undo_manager_include_origin(undo_manager, origin)
  end

  test "can undo without failure when stack is empty" do
    doc = Yex.Doc.new()
    undo_manager = Yex.Nif.undo_manager_new(doc)

    # Just test that it doesn't crash when there's nothing to undo
    Yex.Nif.undo_manager_undo(undo_manager)
  end
end
