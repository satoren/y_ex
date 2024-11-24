defmodule Yex.UndoManager do
  @moduledoc """
  Represents a Y.UndoManager instance.
  """
  defstruct [:reference]

  @doc """
  Creates a new UndoManager for the given document and scope.
  The scope can be a Text, Array, or Map type.
  """
  def new(doc, %Yex.Text{} = scope) do
    case Yex.Nif.undo_manager_new(doc, {:text, scope}) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  def new(doc, %Yex.Array{} = scope) do
    case Yex.Nif.undo_manager_new(doc, {:array, scope}) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  def new(doc, %Yex.Map{} = scope) do
    case Yex.Nif.undo_manager_new(doc, {:map, scope}) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.
  """
  def include_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_include_origin(undo_manager, origin)
  end

  @doc """
  Excludes an origin from being tracked by the UndoManager.
  """
  def exclude_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_exclude_origin(undo_manager, origin)
  end

  @doc """
  Undoes the last tracked change.
  """
  def undo(undo_manager) do
    Yex.Nif.undo_manager_undo(undo_manager)
  end

  @doc """
  Redoes the last undone change.
  """
  def redo(undo_manager) do
    Yex.Nif.undo_manager_redo(undo_manager)
  end

  @doc """
  Expands the scope of the UndoManager to include additional shared types.
  The scope can be a Text, Array, or Map type.
  """
  def expand_scope(undo_manager, %Yex.Text{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:text, scope})
  end

  def expand_scope(undo_manager, %Yex.Array{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:array, scope})
  end

  def expand_scope(undo_manager, %Yex.Map{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:map, scope})
  end

  @doc """
  Stops capturing changes for the current stack item.
  This ensures that the next change will create a new stack item instead of
  being merged with the previous one, even if it occurs within the normal timeout window.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "a")
      UndoManager.stop_capturing(undo_manager)
      Text.insert(text, 1, "b")
      UndoManager.undo(undo_manager)
      # Text.to_string(text) will be "a" (only "b" was removed)
  """
  def stop_capturing(undo_manager) do
    Yex.Nif.undo_manager_stop_capturing(undo_manager)
  end

end
