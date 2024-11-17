defmodule Yex.UndoManager do
  @moduledoc """
  Represents a Y.UndoManager instance.
  """
  defstruct [:reference]

  @doc """
  Creates a new UndoManager for the given document.
  """
  def new(doc) do
    Yex.Nif.undo_manager_new(doc)
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.
  """
  def include_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_include_origin(undo_manager, origin)
  end

  @doc """
  Undoes the last tracked change.
  """
  def undo(undo_manager) do
    Yex.Nif.undo_manager_undo(undo_manager)
  end
end
