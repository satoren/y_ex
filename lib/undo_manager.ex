defmodule Yex.UndoManager do
  use GenServer

  @moduledoc """
  Manages undo/redo operations and observation for Yex shared types.

  The UndoManager maintains both the undo/redo stacks and associated metadata.
  It allows registration of callbacks to observe stack operations:
  - item_added: Called when a new item is added to the undo stack
  - item_updated: Called when an existing item is updated
  - item_popped: Called when an item is popped from the stack (during undo/redo)

  Each type of callback can have only one active handler at a time.
  Registering a new callback replaces any existing one.
  """

  @doc false
  def child_spec({doc, scope} = _init_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :new, [doc, scope]},
      type: :worker
    }
  end

  defmodule Event do
    @moduledoc """
    Represents an undo event from the underlying yrs library.
    """
    @type t :: %__MODULE__{
            id: non_neg_integer(),
            origin: String.t() | nil,
            kind: :text | :array | :map | :xml_fragment | :xml_text,
            delta: term(),
            changed_types: [String.t()]
          }
    defstruct [:id, :origin, :kind, :delta, :changed_types]
  end

  defstruct [
    :pid,
    # ResourceArc<UndoManagerResource>
    :reference
  ]

  @opaque t :: %__MODULE__{
            pid: pid(),
            reference: reference()
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

  defmodule State do
    @moduledoc false
    defstruct item_added_callback: nil,
              item_updated_callback: nil,
              item_popped_callback: nil,
              # Stores metadata for undo events
              metadata: %{},
              # Counter for generating event IDs
              next_id: 0
  end

  # Client API

  @doc """
  Creates a new UndoManager for the given document and scope with default options.
  The scope can be a Text, Array, Map, XmlText, XmlElement, or XmlFragment type.

  ## Errors
  - Returns `{:error, "Invalid scope: expected a struct"}` if scope is not a struct
  - Returns `{:error, "Failed to get branch reference"}` if there's an error accessing the scope
  """
  @spec new(Yex.Doc.t(), struct()) ::
          {:ok, Yex.UndoManager.t()} | {:error, term()}
  def new(doc, scope)
      when is_valid_scope(scope) do
    new_with_options(doc, scope, %Options{})
  end

  @doc """
  Creates a new UndoManager with the given options.

  ## Options

  See `Yex.UndoManager.Options` for available options.

  ## Errors
  - Returns `{:error, "NIF error: <message>"}` if underlying NIF returns an error
  """
  @spec new_with_options(Yex.Doc.t(), struct(), Options.t()) ::
          {:ok, Yex.UndoManager.t()} | {:error, term()}
  def new_with_options(doc, scope, options)
      when is_valid_scope(scope) and
             is_struct(options, Options) do
    case Yex.Nif.undo_manager_new_with_options(doc, scope, options) do
      {:ok, manager} -> {:ok, manager}
      {:error, message} -> {:error, "NIF error: #{message}"}
    end
  end

  @doc """
  Starts the UndoManager process.
  """
  def start_link(doc, scope, options) when is_valid_scope(scope) do
    GenServer.start_link(__MODULE__, {doc, scope, options})
  end

  @doc """
  Registers a callback for when items are added to the undo stack.
  The callback receives an Event struct and should return metadata to be stored.
  Any existing callback will be replaced.

  The callback must be a function that takes one argument (the event).
  """
  def on_item_added(%__MODULE__{pid: pid}, callback) when is_function(callback, 1) do
    GenServer.call(pid, {:set_item_added_callback, callback})
  end

  @doc """
  Registers a callback for when items are updated in the undo stack.
  Any existing callback will be replaced.

  The callback must be a function that takes one argument (the event).
  """
  def on_item_updated(%__MODULE__{pid: pid}, callback) when is_function(callback, 1) do
    GenServer.call(pid, {:set_item_updated_callback, callback})
  end

  @doc """
  Registers a callback for when items are popped from the undo stack.
  Any existing callback will be replaced.

  The callback can be either:
  - fn(id, metadata) -> any() for basic handling
  - fn(id, metadata, event) -> any() for handling with full event data
  """
  def on_item_popped(%__MODULE__{pid: pid}, callback)
      when is_function(callback, 2) or is_function(callback, 3) do
    GenServer.call(pid, {:set_item_popped_callback, callback})
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
  def expand_scope(undo_manager, scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, scope)
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

  @doc """
  Clears all StackItems stored within current UndoManager, effectively resetting its state.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " World")
      UndoManager.clear(undo_manager)
      # All undo/redo history is now cleared
  """
  def clear(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :clear)
  end

  def clear(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :clear)
  end

  # Server Callbacks
  @spec init({Yex.Doc.t(), Yex.SharedType.t(), Options.t()}) :: {:ok, State.t()} | {:stop, term()}
  def init({doc, scope, %Options{} = options}) do
    case Nif.undo_manager_new_with_options(doc, scope, options) do
      {:ok, manager} ->
        # Set up observers immediately since we're the observer process
        :ok = Yex.Nif.undo_manager_observe_item_added(manager, self())
        :ok = Yex.Nif.undo_manager_observe_item_popped(manager, self())
        :ok = Yex.Nif.undo_manager_observe_item_updated(manager, self())
        {:ok, %State{next_id: 0, metadata: %{}}}

      error ->
        {:stop, error}
    end
  end

  def handle_call({:set_item_added_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_added_callback: callback}}
  end

  def handle_call({:set_item_updated_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_updated_callback: callback}}
  end

  def handle_call({:set_item_popped_callback, callback}, _from, state) do
    {:reply, :ok, %{state | item_popped_callback: callback}}
  end

  def handle_call(:clear, _from, state) do
    case Yex.Nif.undo_manager_clear(self()) do
      :ok ->
        # Clear metadata and reset ID counter
        new_state = %{
          state
          | metadata: %{},
            next_id: 0,
            item_added_callback: nil,
            item_updated_callback: nil,
            item_popped_callback: nil
        }

        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  # Handle events from Rust NIF with metadata management
  def handle_info({:item_added, origin, kind, delta}, state) do
    event_with_id = %Event{
      id: state.next_id,
      origin: origin,
      kind: kind,
      delta: delta,
      # We'll need to add this later
      changed_types: []
    }

    new_metadata =
      if state.item_added_callback do
        state.item_added_callback.(event_with_id)
      end

    new_state = %{
      state
      | next_id: state.next_id + 1,
        metadata: Map.put(state.metadata, state.next_id, new_metadata)
    }

    {:noreply, new_state}
  end

  def handle_info({:item_updated, origin, kind, delta}, state) do
    if state.item_updated_callback do
      state.item_updated_callback.(%Event{
        # Updated items don't get new IDs
        id: nil,
        origin: origin,
        kind: kind,
        delta: delta,
        # We'll need to add this later
        changed_types: []
      })
    end

    {:noreply, state}
  end

  def handle_info({:item_popped, origin, kind, delta}, state) do
    # Get metadata for the last item
    stored_metadata = Map.get(state.metadata, state.next_id - 1)

    # Call the appropriate callback based on arity
    case state.item_popped_callback do
      callback when is_function(callback, 2) ->
        callback.(state.next_id - 1, stored_metadata)

      callback when is_function(callback, 3) ->
        callback.(state.next_id - 1, stored_metadata, %Event{
          id: state.next_id - 1,
          origin: origin,
          kind: kind,
          delta: delta,
          # We'll need to add this later
          changed_types: []
        })

      _ ->
        :ok
    end

    {:noreply, %{state | metadata: Map.delete(state.metadata, state.next_id - 1)}}
  end
end
