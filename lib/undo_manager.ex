defmodule Yex.UndoManager do
  defmodule Options do
    @moduledoc """
    UndoManager options.
    """
    defstruct capture_timeout_millis: 500,
              tracked_origins: []

    @type t :: %__MODULE__{
            capture_timeout_millis: non_neg_integer(),
            tracked_origins: list(term())
          }
  end

  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @doc """
  Create a new undo manager for a shared type (text, array, or map).
  """
  @spec new(Yex.Doc.t(), shared_type :: term(), Options.t() | keyword()) :: t()
  def new(%Yex.Doc{} = doc, shared_type, opts \\ []) do
    options = case opts do
      %Options{} -> opts
      keywords when is_list(keywords) -> struct(Options, keywords)
    end

    Yex.Nif.undo_manager_new(doc, shared_type, options.capture_timeout_millis)
  end

  @doc """
  Undo the last change.
  """
  @spec undo(t()) :: :ok | {:error, term()}
  def undo(%__MODULE__{} = manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_undo(manager, nil)
    end)
  end

  @doc """
  Redo the last undone change.
  """
  @spec redo(t()) :: :ok | {:error, term()}
  def redo(%__MODULE__{} = manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_redo(manager, nil)
    end)
  end

  @doc """
  Check if there are any changes that can be undone.
  """
  @spec can_undo?(t()) :: boolean()
  def can_undo?(%__MODULE__{} = manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_can_undo(manager, nil)
    end)
  end

  @doc """
  Check if there are any changes that can be redone.
  """
  @spec can_redo?(t()) :: boolean()
  def can_redo?(%__MODULE__{} = manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_can_redo(manager, nil)
    end)
  end

  @doc """
  Clear all undo/redo history.
  """
  @spec clear(t()) :: :ok | {:error, term()}
  def clear(%__MODULE__{} = manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_clear(manager, nil)
    end)
  end

  @doc """
  Add an origin to track for undo/redo operations.
  """
  @spec add_tracked_origin(t(), term()) :: :ok
  def add_tracked_origin(%__MODULE__{} = manager, origin) do
    Yex.Nif.undo_manager_add_tracked_origin(manager, origin)
  end

  @doc """
  Remove an origin from tracking.
  """
  @spec remove_tracked_origin(t(), term()) :: :ok
  def remove_tracked_origin(%__MODULE__{} = manager, origin) do
    Yex.Nif.undo_manager_remove_tracked_origin(manager, origin)
  end
end
