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
end
