defmodule Yex.UndoManager do
  alias Yex.{Nif, UndoObserver}

  @moduledoc """
  Manages undo/redo operations for Yex shared types.
  """

  defstruct [:reference, observers: %{}]

  @type t :: %__MODULE__{
          reference: reference(),
          observers: %{optional(:item_added | :item_popped) => pid}
        }

  @doc false
  defguard is_valid_scope(scope)
           when is_struct(scope, Yex.Text) or
                  is_struct(scope, Yex.Array) or
                  is_struct(scope, Yex.Map) or
                  is_struct(scope, Yex.XmlFragment) or
                  is_struct(scope, Yex.XmlElement) or
                  is_struct(scope, Yex.XmlText)

  defmodule Options do
    @moduledoc """
    Options for creating a new UndoManager.
    """
    defstruct capture_timeout: 500

    @type t :: %__MODULE__{
            capture_timeout: non_neg_integer()
          }
  end

  @doc """
  Creates a new UndoManager for the given scope.
  """
  def new(doc, scope) when is_valid_scope(scope) do
    case Nif.undo_manager_new(doc, scope) do
      {:ok, reference} -> {:ok, %__MODULE__{reference: reference}}
      error -> error
    end
  end

  @doc """
  Creates a new UndoManager with the specified options.
  """
  def new_with_options(doc, scope, %Options{} = options) when is_valid_scope(scope) do
    case Nif.undo_manager_new_with_options(doc, scope, options) do
      {:ok, reference} -> {:ok, %__MODULE__{reference: reference}}
      {:error, reason} -> {:error, "NIF error: #{reason}"}
    end
  end

  @doc """
  Observes when items are added to the undo stack.
  The callback receives an event with the item ID and should return metadata to store.
  """
  def observe_item_added(%__MODULE__{reference: ref} = manager, callback)
      when is_function(callback, 1) do
    case start_observer(manager, :item_added, callback) do
      {:ok, pid} ->
        case Nif.undo_manager_observe_item_added(ref, pid) do
          :ok -> {:ok, %{manager | observers: Map.put(manager.observers, :item_added, pid)}}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Observes when items are popped from the undo stack.
  The callback receives the item ID and its metadata.
  """
  def observe_item_popped(%__MODULE__{reference: ref} = manager, callback)
      when is_function(callback, 2) or is_function(callback, 3) do
    case start_observer(manager, :item_popped, callback) do
      {:ok, pid} ->
        case Nif.undo_manager_observe_item_popped(ref, pid) do
          :ok -> {:ok, %{manager | observers: Map.put(manager.observers, :item_popped, pid)}}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Gets metadata associated with an undo stack item.
  """
  def get_metadata(%__MODULE__{} = manager, type, id) when type in [:item_added, :item_popped] do
    case Map.get(manager.observers, type) do
      nil -> {:error, :no_observer}
      pid -> UndoObserver.get_metadata(pid, id)
    end
  end

  @doc """
  Undoes the last change in the undo stack.
  """
  def undo(%__MODULE__{reference: ref} = _manager) do
    Nif.undo_manager_undo(ref)
  end

  @doc """
  Redoes the last undone change.
  """
  def redo(%__MODULE__{reference: ref} = _manager) do
    Nif.undo_manager_redo(ref)
  end

  @doc """
  Cleans up all observers and clears the undo/redo stacks.
  """
  def clear(%__MODULE__{reference: ref} = manager) do
    Enum.each(manager.observers, fn {_type, pid} ->
      GenServer.stop(pid)
    end)

    manager = %{manager | observers: %{}}
    Nif.undo_manager_clear(ref)
    {:ok, manager}
  end

  @doc """
  Stops capturing changes, ensuring subsequent changes create new undo stack items.
  """
  def stop_capturing(%__MODULE__{reference: ref} = _manager) do
    Nif.undo_manager_stop_capturing(ref)
  end

  @doc """
  Includes an origin in the set of tracked origins.
  """
  def include_origin(%__MODULE__{reference: ref} = _manager, origin) do
    Nif.undo_manager_include_origin(ref, origin)
  end

  @doc """
  Excludes an origin from the set of tracked origins.
  """
  def exclude_origin(%__MODULE__{reference: ref} = _manager, origin) do
    Nif.undo_manager_exclude_origin(ref, origin)
  end

  @doc """
  Expands the scope to include additional shared types.
  """
  def expand_scope(%__MODULE__{reference: ref} = _manager, scope)
      when is_valid_scope(scope) do
    Nif.undo_manager_expand_scope(ref, scope)
  end

  # Private functions

  defp start_observer(%__MODULE__{reference: ref}, type, callback) do
    UndoObserver.start_link({type, ref, callback})
  end
end
