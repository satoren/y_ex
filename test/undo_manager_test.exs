defmodule Yex.UndoManagerTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, UndoManager}

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    {:ok, manager} = UndoManager.new(doc)
    {:ok, doc: doc, text: text, manager: manager}
  end

  test "basic undo/redo operations", %{doc: _doc, text: text, manager: manager} do
    Text.insert(text, 0, "Hello")
    assert Text.to_string(text) == "Hello"

    :ok = UndoManager.undo(manager)
    assert Text.to_string(text) == ""

    :ok = UndoManager.redo(manager)
    assert Text.to_string(text) == "Hello"
  end

  test "undo/redo within transaction", %{doc: doc, text: text, manager: manager} do
    Doc.transaction(doc, fn ->
      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " World")
    end)
    assert Text.to_string(text) == "Hello World"

    :ok = UndoManager.undo(manager)
    assert Text.to_string(text) == ""

    :ok = UndoManager.redo(manager)
    assert Text.to_string(text) == "Hello World"
  end

  test "multiple undo/redo steps", %{doc: _doc, text: text, manager: manager} do
    Text.insert(text, 0, "First")
    Text.insert(text, 5, " Second")
    Text.insert(text, 12, " Third")
    assert Text.to_string(text) == "First Second Third"

    :ok = UndoManager.undo(manager)
    assert Text.to_string(text) == "First Second"

    :ok = UndoManager.undo(manager)
    assert Text.to_string(text) == "First"

    :ok = UndoManager.redo(manager)
    assert Text.to_string(text) == "First Second"

    :ok = UndoManager.redo(manager)
    assert Text.to_string(text) == "First Second Third"
  end

  test "can_undo? and can_redo?", %{doc: _doc, text: text, manager: manager} do
    refute UndoManager.can_undo?(manager)
    refute UndoManager.can_redo?(manager)

    Text.insert(text, 0, "Hello")
    assert UndoManager.can_undo?(manager)
    refute UndoManager.can_redo?(manager)

    UndoManager.undo(manager)
    refute UndoManager.can_undo?(manager)
    assert UndoManager.can_redo?(manager)
  end

  test "clear undo history", %{doc: _doc, text: text, manager: manager} do
    Text.insert(text, 0, "Hello")
    assert UndoManager.can_undo?(manager)

    :ok = UndoManager.clear(manager)
    refute UndoManager.can_undo?(manager)
    refute UndoManager.can_redo?(manager)
  end

  test "tracked origins", %{doc: doc, text: text, manager: manager} do
    UndoManager.include_origin(manager, "tracked_change")

    Doc.transaction(doc, "tracked_change", fn ->
      Text.insert(text, 0, "Tracked")
    end)
    assert UndoManager.can_undo?(manager)

    UndoManager.clear(manager)

    Doc.transaction(doc, "untracked_change", fn ->
      Text.insert(text, 0, "Untracked")
    end)
    refute UndoManager.can_undo?(manager)
  end

  test "nested transactions", %{doc: doc, text: text, manager: manager} do
    Doc.transaction(doc, fn ->
      Text.insert(text, 0, "Outer")

      Doc.transaction(doc, fn ->
        Text.insert(text, 5, " Inner")
      end)
    end)
    assert Text.to_string(text) == "Outer Inner"

    :ok = UndoManager.undo(manager)
    assert Text.to_string(text) == ""

    :ok = UndoManager.redo(manager)
    assert Text.to_string(text) == "Outer Inner"
  end

  test "multiple shared types", %{doc: doc} do
    text1 = Doc.get_text(doc, "text1")
    text2 = Doc.get_text(doc, "text2")

    {:ok, manager1} = UndoManager.new(doc)
    {:ok, manager2} = UndoManager.new(doc)

    Text.insert(text1, 0, "Text 1")
    Text.insert(text2, 0, "Text 2")

    assert Text.to_string(text1) == "Text 1"
    assert Text.to_string(text2) == "Text 2"

    :ok = UndoManager.undo(manager1)
    assert Text.to_string(text1) == ""
    assert Text.to_string(text2) == "Text 2"

    :ok = UndoManager.undo(manager2)
    assert Text.to_string(text1) == ""
    assert Text.to_string(text2) == ""
  end

  test "undo manager with custom options", %{doc: doc, text: text} do
    {:ok, manager} = UndoManager.new(doc, %UndoManager.Options{
      capture_timeout_millis: 1000,
      tracked_origins: ["origin1", "origin2"]
    })

    Doc.transaction(doc, "origin1", fn ->
      Text.insert(text, 0, "Tracked 1")
    end)
    assert UndoManager.can_undo?(manager)

    UndoManager.clear(manager)

    Doc.transaction(doc, "origin2", fn ->
      Text.insert(text, 0, "Tracked 2")
    end)
    assert UndoManager.can_undo?(manager)

    UndoManager.clear(manager)

    Doc.transaction(doc, "origin3", fn ->
      Text.insert(text, 0, "Untracked")
    end)
    refute UndoManager.can_undo?(manager)
  end
end
