defmodule Yex.UndoMetadataServer do
  @moduledoc """
  A GenServer that manages metadata for undo/redo events in coordination with the Rust NIF layer.

  ## Architecture and Event ID Flow

  This server solves a key challenge in the Yrs undo manager implementation: maintaining metadata
  across the Rust-Elixir boundary. Here's how it works:

  1. When an undo item is added in Rust, we need to:
     - Generate a unique event ID (UUID)
     - Store this ID in the Rust stack item's metadata
     - Allow Elixir callbacks to associate custom metadata with this ID
     - Preserve this metadata for future updates and when the item is popped

  2. The flow is:
     - Rust generates a UUID when an item is added (`undo_manager_observe_item_added`)
     - This ID is stored in the Rust stack item's mutable metadata
     - The event and ID are sent to this GenServer
     - Elixir callbacks can add custom metadata, which we store in the `metadata` map in GenServer state
     - Future updates/pops reference this ID to retrieve and update the metadata

  ## Why This Design?

  We can't directly modify the Rust event's metadata from Elixir callbacks because:
  1. The Rust event is temporary and only exists during the callback
  2. NIFs don't allow complex data modifications across the boundary
  3. We need persistent metadata storage between events

  """
  use GenServer
  alias Yex.UndoManager.Event

  # Client API
  def start_link(rust_ref) do
    GenServer.start_link(__MODULE__, rust_ref)
  end

  def set_item_added_callback(pid, callback) do
    GenServer.call(pid, {:set_item_added_callback, callback})
  end

  def set_item_updated_callback(pid, callback) do
    GenServer.call(pid, {:set_item_updated_callback, callback})
  end

  def set_item_popped_callback(pid, callback) do
    GenServer.call(pid, {:set_item_popped_callback, callback})
  end

  def clear_metadata(pid) do
    GenServer.call(pid, :clear_metadata)
  end

  # Server Implementation
  defmodule State do
    @moduledoc """
    Internal state for the UndoMetadataServer.

    Fields:
      * rust_ref - Reference to the Rust undo manager instance
      * item_added_callback - Optional function called when new undo items are added
      * item_updated_callback - Optional function called when existing undo items are updated
      * item_popped_callback - Optional function called when items are popped from the undo stack
      * metadata - Map of event_id => UndoMetadata entries storing persistent metadata for undo events
          The metadata map structure is:
          %{
            event_id => %UndoMetadata{
              event_id: UUID,
              data: map()  # Custom metadata provided by callbacks
            }
          }
    """
    defstruct [
      :rust_ref,
      :item_added_callback,
      :item_updated_callback,
      :item_popped_callback,
      metadata: %{}
    ]
  end

  @impl true
  def init(rust_ref) do
    :ok = Yex.Nif.undo_manager_observe_item_added(rust_ref, self())
    :ok = Yex.Nif.undo_manager_observe_item_popped(rust_ref, self())
    :ok = Yex.Nif.undo_manager_observe_item_updated(rust_ref, self())

    {:ok, %State{rust_ref: rust_ref}}
  end

  @impl true
  def handle_call({:set_item_added_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_added_callback: callback}}
  end

  @impl true
  def handle_call({:set_item_updated_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_updated_callback: callback}}
  end

  @impl true
  def handle_call({:set_item_popped_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_popped_callback: callback}}
  end

  @impl true
  def handle_call(:clear_metadata, _from, state) do
    {:reply, :ok, %{state | metadata: %{}}}
  end

  @impl true
  def handle_info({:item_added, event}, state) do
    elixir_metadata = %Yex.UndoManager.UndoMetadata{
      event_id: event.meta.event_id,
      data: %{}
    }

    # Convert to proper Event struct with initial metadata
    event = %Yex.UndoManager.Event{
      meta: elixir_metadata,
      origin: event.origin,
      kind: event.kind,
      changed_parent_types: event.changed_parent_types
    }

    if state.item_added_callback do
      callback_metadata = state.item_added_callback.(event)

      preserved_metadata = %Yex.UndoManager.UndoMetadata{
        event_id: event.meta.event_id,
        data: callback_metadata
      }

      new_state = %{
        state
        | metadata: Map.put(state.metadata, event.meta.event_id, preserved_metadata)
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:item_updated, event}, state) do
    event_id = event.meta.event_id
    stored_meta = Map.get(state.metadata, event_id)

    event = %Event{
      meta: stored_meta,
      origin: event.origin,
      kind: event.kind,
      changed_parent_types: event.changed_parent_types
    }

    new_meta =
      case state.item_updated_callback do
        nil ->
          stored_meta

        callback ->
          case callback.(event) do
            nil ->
              stored_meta

            metadata when is_map(metadata) ->
              %Yex.UndoManager.UndoMetadata{event_id: event_id, data: metadata}

            _ ->
              stored_meta
          end
      end

    new_state = %{
      state
      | metadata: Map.put(state.metadata, event_id, new_meta)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:item_popped, id, event}, state) do
    stored_meta = Map.get(state.metadata, id)

    event =
      if stored_meta do
        %{event | meta: stored_meta}
      else
        %{event | meta: struct(Yex.UndoManager.UndoMetadata, %{event_id: id, data: %{}})}
      end

    if state.item_popped_callback do
      state.item_popped_callback.(id, event)
    end

    {:noreply, state}
  end
end
