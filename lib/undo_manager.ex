defmodule Yex.UndoManager do
  require Logger

  @moduledoc """
  Manages undo/redo operations and observation for Yex shared types.

  The UndoManager maintains both the undo/redo stacks and associated metadata.
  It allows registration of callbacks to observe stack operations:
  - item_added: Called when a new item is added to the undo stack
  - item_updated: Called when an existing item is updated
  - item_popped: Called when an item is popped from the stack (during undo/redo)

  Each type of callback can have only one active handler at a time.
  Registering a new callback replaces any existing one.

  ## Understanding Yrs and Transaction Synchronization

  Yrs (the underlying CRDT library) uses an eventual consistency model where changes are
  synchronized asynchronously. The UndoManager batches changes within a capture timeout window
  (default 500ms) to group related operations together.

  To ensure reliable undo/redo behavior, use `stop_capturing/1` when you need to explicitly
  separate operations into distinct undo steps. This is preferable to relying on timing or
  the capture timeout, as it guarantees proper transaction boundaries.

  ## Basic Usage

      # Create a new document and text type
      {:ok, doc} = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "mytext")

      # Create an undo manager for the text
      {:ok, manager} = Yex.UndoManager.new(doc, text)

      # Make some changes that should be one undo operation
      Yex.Text.insert(text, 0, "Hello")
      Yex.Text.insert(text, 5, " World")

      # Stop capturing to ensure the next change is a separate undo operation
      Yex.UndoManager.stop_capturing(manager)

      # This will be a separate undo operation
      Yex.Text.insert(text, 11, "!")

      # Undo the last change (removes "!")
      Yex.UndoManager.undo(manager)

      # Undo the previous changes (removes "Hello World")
      Yex.UndoManager.undo(manager)

  ## Working with Origins

      # Track changes from specific origins
      Yex.UndoManager.include_origin(manager, "user1")

      # Ignore changes from specific origins
      Yex.UndoManager.exclude_origin(manager, "system")

  ## Observing Changes

      # Register a callback for when items are added
      Yex.UndoManager.on_item_added(manager, fn event ->
        IO.puts "New undo item added: \#{inspect(event)}"
      end)

      # Register a callback for when items are popped
      Yex.UndoManager.on_item_popped(manager, fn id, event ->
        IO.puts "Item \#{id} was popped: \#{inspect(event)}"
      end)

  ## Managing Capture Groups

      # Stop capturing changes to create a new undo group
      Yex.Text.insert(text, 0, "First ")
      Yex.UndoManager.stop_capturing(manager)
      Yex.Text.insert(text, 6, "Second ")
      # Now these will be separate undo operations

  ## Capture Timeout Configuration

  In addition to capture groups, the UndoManager's capture timeout also effects batching of undo items.
  It determines how long it will wait to batch related operations together into a single undo step.
  You can configure this when creating the UndoManager:

      # Create an UndoManager with a 1-second capture timeout
      {:ok, manager} = UndoManager.new_with_options(doc, text, %Options{capture_timeout: 1000})

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

    Before sending the event to Elixir, we add an event_id to the meta field.
    This is used by the metadata GenServer to track the metadata for each stack item.
    It is stored in meta so that it persists with the Stack Item in yrs.

    """
    @type t :: %__MODULE__{
            meta: %{event_id: String.t()} | Yex.UndoManager.UndoMetadata.t(),
            origin: String.t() | nil,
            kind: :undo | :redo,
            changed_parent_types: [String.t()]
          }
    defstruct [:meta, :origin, :kind, :changed_parent_types]
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
    Metadata for undo events, including a unique identifier (from undo.rs) and custom data (managed by UndoMetadataServer).
    """
    @type t :: %__MODULE__{
            event_id: String.t(),
            data: map()
          }
    defstruct [:event_id, data: %{}]
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
    # ensure_metadata_server will only return {:ok, manager} upon starting server successfully
    with {:ok, manager} <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_added_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_added(manager.reference, manager.metadata_server_pid) do
      {:ok, manager}
    else
      error ->
        error
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
    # ensure_metadata_server will only return {:ok, manager} upon starting server successfully
    with {:ok, manager} <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_updated_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_updated(
             manager.reference,
             manager.metadata_server_pid
           ) do
      {:ok, manager}
    else
      error ->
        error
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
    # ensure_metadata_server will only return {:ok, manager} upon starting server successfully
    with {:ok, manager} <- ensure_metadata_server(manager),
         :ok <-
           Yex.UndoMetadataServer.set_item_popped_callback(manager.metadata_server_pid, callback),
         :ok <-
           Yex.Nif.undo_manager_observe_item_popped(
             manager.reference,
             manager.metadata_server_pid
           ) do
      {:ok, manager}
    else
      error ->
        error
    end
  end

  # Helper function to ensure observer process exists
  defp ensure_metadata_server(%__MODULE__{} = manager) do
    case manager.metadata_server_pid do
      nil ->
        case Yex.UndoMetadataServer.start_link(manager.reference) do
          {:ok, pid} ->
            {:ok, %{manager | metadata_server_pid: pid}}

          error ->
            error
        end

      _pid ->
        {:ok, manager}
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
  Stops capturing changes for the current stack item and ensures the next change creates a new undo operation.

  Due to Yrs' eventual consistency model, changes are typically batched within a capture timeout window.
  Using `stop_capturing/1` provides explicit control over undo operation boundaries, which is more
  reliable than depending on timing.

  ## When to use

  - When you want to ensure changes are split into separate undo operations
  - After completing a logical group of changes that should be undone together
  - Before starting a new set of changes that should be undone separately

  ## Example

      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      # These changes will be grouped together
      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " ")
      Text.insert(text, 6, "World")

      # Ensure the next change is a separate undo operation
      UndoManager.stop_capturing(undo_manager)

      # This will be a separate undo operation
      Text.insert(text, 11, "!")

      UndoManager.undo(undo_manager)  # Removes "!"
      assert Text.to_string(text) == "Hello World"

      UndoManager.undo(undo_manager)  # Removes "Hello World"
      assert Text.to_string(text) == ""
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
      {:ok, {}} ->
        if manager.metadata_server_pid do
          :ok = Yex.UndoMetadataServer.clear_metadata(manager.metadata_server_pid)
        end

        :ok

      error ->
        error
    end
  end

  @doc """
  Checks if the undo manager has items in the undo stack.
  """
  def can_undo?(manager) do
    Yex.Nif.undo_manager_can_undo(manager.reference)
  end

  @doc """
  Checks if the undo manager has items in the redo stack.
  """
  def can_redo?(manager) do
    Yex.Nif.undo_manager_can_redo(manager.reference)
  end
end
