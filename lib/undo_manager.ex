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


end
