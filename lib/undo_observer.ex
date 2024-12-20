defmodule Yex.UndoObserver do
  use GenServer

  @moduledoc """
  GenServer implementation for handling undo/redo operation observations.
  """

  defmodule Event do
    @moduledoc """
    Represents an event from the UndoManager when a new stack item is created.
    """
    @type t :: %__MODULE__{
            id: non_neg_integer(),
            origin: binary() | nil,
            changed_types: [String.t()]
          }

    defstruct [:id, :origin, :changed_types]
  end

  # Client API

  @doc """
  Starts an observer process for the given undo manager reference and callback.
  """
  def start_link({type, ref, callback}) when type in [:item_added, :item_popped] do
    GenServer.start_link(__MODULE__, {type, ref, callback})
  end

  @doc """
  Gets metadata associated with an undo stack item.
  """
  def get_metadata(pid, id) do
    GenServer.call(pid, {:get_metadata, id})
  end

  # Server Callbacks

  @impl true
  def init({type, ref, callback}) do
    {:ok,
     %{
       type: type,
       ref: ref,
       callback: callback,
       metadata: %{}
     }}
  end

  @impl true
  def handle_info(
        {:item_added, event},
        %{type: :item_added, callback: callback, metadata: metadata} = state
      ) do
    new_metadata = callback.(event)
    {:noreply, %{state | metadata: Map.put(metadata, event.id, new_metadata)}}
  end

  @impl true
  def handle_info(
        {:item_popped, id, event},
        %{type: :item_popped, callback: callback, metadata: metadata} = state
      ) do
    stored_metadata = Map.get(metadata, id)

    case callback do
      callback when is_function(callback, 2) -> callback.(id, stored_metadata)
      callback when is_function(callback, 3) -> callback.(id, stored_metadata, event)
    end

    {:noreply, %{state | metadata: Map.delete(metadata, id)}}
  end

  @impl true
  def handle_call({:get_metadata, id}, _from, %{metadata: metadata} = state) do
    result =
      case Map.fetch(metadata, id) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :not_found}
      end

    {:reply, result, state}
  end
end
