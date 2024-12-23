defmodule Yex.UndoManager do
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

    Maps to the Rust struct:
    ```rust
    pub struct Event<M> {
        meta: M,
        origin: Option<Origin>,
        kind: EventKind,
        changed_parent_types: Vec<BranchPtr>,
    }

    WE ADD AN ID TO meta as event.meta.event_id
    Event.id is added in undo.rs for a specific reason: we need a unique id to track each stack item and no unique info is provided in the Event.
    So when we get an event from Rust, we add an id to it.
    This is used by the metadata GenServer to track the metadata for each stack item.
    Why not use yrs UndoManager to track the metadata?  Because we cannot update the mutable metadata in a NIF callback context without potentially blocking.


    ```
    """
    @type t :: %__MODULE__{
            id: String.t(),
            meta: term(),
            origin: String.t() | nil,
            kind: :undo | :redo,
            changed_parent_types: [String.t()]
          }
    defstruct [:id, :meta, :origin, :kind, :changed_parent_types]
  end

  defstruct [
    :reference,
    :metadata_server_pid
  ]

  @type t :: %__MODULE__{
          reference: reference(),
          metadata_server_pid: pid() | nil
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

  defmodule UndoMetadata do
    @moduledoc """
    Metadata for undo events, including a unique identifier.
    """
    @type t :: %__MODULE__{
            event_id: String.t()
          }
    defstruct [:event_id]
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
  def new(doc, scope) when is_valid_scope(scope) do
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
      {:ok, rust_ref} ->
        {:ok,
         %__MODULE__{
           reference: rust_ref,
           metadata_server_pid: nil
         }}

      error ->
        error
    end
  end

  @typedoc """
  Callback for when items are added to the undo stack.
  Receives the event and should return metadata to be stored.
  """
  @type item_added_callback :: (Event.t() -> term())

  @doc """
  Registers a callback for when items are added to the undo stack.
  The callback receives an Event struct and should return metadata to be stored.
  Any existing callback will be replaced.

  The callback must be a function that takes one argument (the event).
  """
  @spec on_item_added(t(), item_added_callback()) :: {:ok, t()} | {:error, term()}
  def on_item_added(%__MODULE__{} = manager, callback) when is_function(callback, 1) do
    with manager <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_added_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_added(manager.reference, manager.metadata_server_pid) do
      {:ok, manager}
    end
  end

  @typedoc """
  Callback for when items are updated in the undo stack.
  Receives the event but does not store metadata.
  """
  @type item_updated_callback :: (Event.t() -> term())

  @doc """
  Registers a callback for when items are updated in the undo stack.
  Any existing callback will be replaced.

  The callback must be a function that takes one argument (the event).
  """
  @spec on_item_updated(t(), item_updated_callback()) :: {:ok, t()} | {:error, term()}
  def on_item_updated(%__MODULE__{} = manager, callback) when is_function(callback, 1) do
    with manager <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_updated_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_updated(
             manager.reference,
             manager.metadata_server_pid
           ) do
      {:ok, manager}
    end
  end

  @typedoc """
  Callback for when items are popped from the undo stack.
  Receives the event ID and event data.
  """
  @type item_popped_callback :: (String.t(), Event.t() -> term())

  @doc """
  Registers a callback for when items are popped from the undo stack.

  The callback receives the event ID and event data.

  """
  @spec on_item_popped(t(), item_popped_callback()) :: {:ok, t()} | {:error, term()}
  def on_item_popped(%__MODULE__{} = manager, callback) when is_function(callback, 2) do
    with manager <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_popped_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_popped(
             manager.reference,
             manager.metadata_server_pid
           ) do
      {:ok, manager}
    end
  end

  # Helper function to ensure observer process exists
  defp ensure_metadata_server(%__MODULE__{} = manager) do
    case manager.metadata_server_pid do
      nil ->
        {:ok, pid} = Yex.UndoMetadataServer.start_link(manager.reference)
        %{manager | metadata_server_pid: pid}

      _pid ->
        manager
    end
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.
  """
  def include_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_include_origin(undo_manager.reference, origin)
  end

  @doc """
  Excludes an origin from being tracked by the UndoManager.
  Any changes made with this origin will not be tracked for undo/redo operations.

  ## Example:
      undo_manager = UndoManager.new(doc, text)
      UndoManager.exclude_origin(undo_manager, "my-origin")
  """
  def exclude_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_exclude_origin(undo_manager.reference, origin)
  end

  @doc """
  Undoes the last tracked change.
  """
  def undo(undo_manager) do
    Yex.Nif.undo_manager_undo(undo_manager.reference)
  end

  @doc """
  Redoes the last undone change.
  """
  def redo(undo_manager) do
    Yex.Nif.undo_manager_redo(undo_manager.reference)
  end

  @doc """
  Expands the scope of the UndoManager to include additional shared types.
  The scope can be a Text, Array, or Map type.
  """
  def expand_scope(undo_manager, scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager.reference, scope)
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
    Yex.Nif.undo_manager_stop_capturing(undo_manager.reference)
  end

  @doc """
  Stops observing item added events and restores default metadata observer.
  """
  def unobserve_item_added(%__MODULE__{} = manager) do
    if manager.metadata_server_pid do
      :ok = Yex.UndoMetadataServer.set_item_added_callback(manager.metadata_server_pid, nil)
    end

    # Call Rust to unobserve and restore default observer
    :ok = Yex.Nif.undo_manager_unobserve_item_added(manager.reference)
    manager
  end

  @doc """
  Stops observing item updated events.
  """
  def unobserve_item_updated(%__MODULE__{} = manager) do
    if manager.metadata_server_pid do
      :ok = Yex.UndoMetadataServer.set_item_updated_callback(manager.metadata_server_pid, nil)
    end

    :ok = Yex.Nif.undo_manager_unobserve_item_updated(manager.reference)
    manager
  end

  @doc """
  Stops observing item popped events.
  """
  def unobserve_item_popped(%__MODULE__{} = manager) do
    if manager.metadata_server_pid do
      :ok = Yex.UndoMetadataServer.set_item_popped_callback(manager.metadata_server_pid, nil)
    end

    :ok = Yex.Nif.undo_manager_unobserve_item_popped(manager.reference)
    manager
  end

  @doc """
  Clears all StackItems stored within current UndoManager, effectively resetting its state.
  Does not affect registered callbacks.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " World")
      UndoManager.clear(undo_manager)
      # All undo/redo history is now cleared, but callbacks remain
  """
  def clear(%__MODULE__{} = manager) do
    case Yex.Nif.undo_manager_clear(manager.reference) do
      :ok ->
        if manager.metadata_server_pid do
          Yex.UndoMetadataServer.clear_metadata(manager.metadata_server_pid)
        end

        :ok

      error ->
        error
    end
  end

  def can_undo?(manager) do
    Yex.Nif.undo_manager_can_undo(manager.reference)
  end
end
