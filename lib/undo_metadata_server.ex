defmodule Yex.UndoMetadataServer do
  @moduledoc false
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
    @moduledoc false
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
    # Convert the metadata map to a struct
    event = %{event | meta: struct(Yex.UndoManager.UndoMetadata, event.meta)}

    if state.item_added_callback do
      # Get callback metadata and ensure event_id is preserved
      callback_metadata = state.item_added_callback.(event)

      preserved_metadata =
        case callback_metadata do
          nil ->
            event.meta

          metadata when is_map(metadata) ->
            Map.merge(metadata, %{event_id: event.meta.event_id})

          _ ->
            event.meta
        end

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
            nil -> stored_meta
            meta -> meta
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
    # Get the stored metadata for this event
    stored_meta = Map.get(state.metadata, id)

    # Create event with the stored metadata if it exists
    event =
      if stored_meta do
        %{event | meta: stored_meta}
      else
        # Fallback to creating a new metadata struct with the id
        %{event | meta: struct(Yex.UndoManager.UndoMetadata, Map.put(event.meta, :event_id, id))}
      end

    if state.item_popped_callback do
      state.item_popped_callback.(id, event)
    end

    {:noreply, state}
  end
end
