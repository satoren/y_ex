# Run with: mix run bench/undo_manager_bench.exs

doc_setup = fn _ ->
  doc = Yex.Doc.new()
  text = Yex.Doc.get_text(doc, "mytext")
  {:ok, manager} = Yex.UndoManager.new(doc, text)
  {doc, text, manager}
end

Benchee.run(
  %{
    "single operation undo/redo" => fn input ->
      {_doc, text, manager} = input
      Yex.Text.insert(text, 0, "Hello")
      Yex.UndoManager.undo(manager)
      Yex.UndoManager.redo(manager)
    end,

    "multiple operations batch" => fn input ->
      {_doc, text, manager} = input
      Yex.Text.insert(text, 0, "Hello")
      Yex.Text.insert(text, 5, " World")
      Yex.Text.insert(text, 11, "!")
      Yex.UndoManager.undo(manager)
    end,

    "multiple operations separate" => fn input ->
      {_doc, text, manager} = input
      Yex.Text.insert(text, 0, "Hello")
      Yex.UndoManager.stop_capturing(manager)
      Yex.Text.insert(text, 5, " World")
      Yex.UndoManager.stop_capturing(manager)
      Yex.Text.insert(text, 11, "!")
      Yex.UndoManager.undo(manager)
      Yex.UndoManager.undo(manager)
      Yex.UndoManager.undo(manager)
    end,

    "observer callbacks" => fn input ->
      {_doc, text, manager} = input
      {:ok, manager} = Yex.UndoManager.on_item_added(manager, fn _event -> %{} end)
      {:ok, manager} = Yex.UndoManager.on_item_updated(manager, fn _event -> nil end)
      {:ok, manager} = Yex.UndoManager.on_item_popped(manager, fn _id, _event -> nil end)
      Yex.Text.insert(text, 0, "Test")
      Yex.UndoManager.undo(manager)
    end,

    "scope expansion" => fn input ->
      {doc, text, manager} = input
      array = Yex.Doc.get_array(doc, "myarray")
      Yex.UndoManager.expand_scope(manager, array)
      Yex.Text.insert(text, 0, "Hello")
      Yex.Array.push(array, "World")
      Yex.UndoManager.undo(manager)
    end
  },
  before_each: doc_setup,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)
