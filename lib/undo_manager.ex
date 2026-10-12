defmodule Yex.UndoManager.Options do
  @moduledoc """
  Options for creating an UndoManager.

  * `:capture_timeout` - Time in milliseconds to wait before creating a new capture group
  * `:tracked_origins` - Origins to track from the start, as if each had been passed to
    `Yex.UndoManager.include_origin/2`. `nil` (the default) tracks only transactions
    without an origin. See "Tracked origins" in `Yex.UndoManager`.
  """
  # Default from Yrs
  defstruct capture_timeout: 500, tracked_origins: nil

  @type t :: %__MODULE__{
          capture_timeout: non_neg_integer(),
          tracked_origins: [term()] | nil
        }
end

defmodule Yex.UndoManager.StackItemEvent do
  @moduledoc """
  A stack item was added, updated or popped. Delivered by `Yex.UndoManager.observe/2`.

  * `:type` - `:added` when a captured change created a new item, `:updated` when it was
    merged into the last item (within `capture_timeout`), `:popped` when `undo/1` or
    `redo/1` applied the item.
  * `:kind` - for `:added` and `:updated`, the stack the item is on: `:redo` when the
    change came from an undo, `:undo` otherwise. For `:popped`, `:undo` when popped by
    `undo/1` and `:redo` when popped by `redo/1`.
  * `:item` - the item's id, stable for its whole life. Use it with
    `Yex.UndoManager.put_meta/3` and `Yex.UndoManager.get_meta/2`.
  * `:origin` - the origin of the transaction that caused the event: the term given to
    `Yex.Doc.transaction/3`, `nil`, or the `%Yex.UndoManager{}` for undo and redo.
  * `:meta` - the item's meta at the time of the event, `nil` until set.
  """
  defstruct [:type, :kind, :item, :origin, :meta]

  @type t :: %__MODULE__{
          type: :added | :updated | :popped,
          kind: :undo | :redo,
          item: pos_integer(),
          origin: term(),
          meta: term()
        }
end

defmodule Yex.UndoManager.StackClearedEvent do
  @moduledoc """
  `Yex.UndoManager.clear/1` emptied the stacks. Delivered by `Yex.UndoManager.observe/2`
  only when at least one stack held items.

  Each flag is `true` when that stack held items before the clear.
  """
  defstruct [:undo_stack_cleared, :redo_stack_cleared]

  @type t :: %__MODULE__{undo_stack_cleared: boolean(), redo_stack_cleared: boolean()}
end

defmodule Yex.UndoManager do
  alias Yex.UndoManager.Options
  alias Yex.Doc
  require Yex.Doc

  defguard is_valid_scope(scope)
           when is_struct(scope, Yex.Text) or
                  is_struct(scope, Yex.Array) or
                  is_struct(scope, Yex.Map) or
                  is_struct(scope, Yex.XmlText) or
                  is_struct(scope, Yex.XmlElement) or
                  is_struct(scope, Yex.XmlFragment)

  @moduledoc """
  Represents a Y.UndoManager instance.

  ## Scope

  `new/2` and `new_with_options/3` take a Text, Array, Map, XmlText, XmlElement or
  XmlFragment. `expand_scope/2` also takes a WeakLink. Any other value raises
  `FunctionClauseError`.

  A scope must belong to the manager's document; one from another document raises
  `ArgumentError`. A scope from another `Yex.Doc` of the same subdocument (for example
  the struct a parent's `Yex.Map.fetch/2` returns) is accepted. Calls are serialized
  only through the manager's `Yex.Doc`, so when another process has a transaction open
  through the scope's `Yex.Doc`, the call raises `Yex.TransactionAcqError` instead of
  waiting for it.

  ## Tracked origins

  A transaction's origin is the term passed to `Yex.Doc.transaction/3`, or `nil`
  when none was given. The manager only captures changes from origins it tracks:

  * With no tracked origins (the default), it captures only transactions whose
    origin is `nil`.
  * Once at least one origin is tracked, it captures only transactions with a
    tracked origin, and transactions with a `nil` origin are no longer captured.
    Removing every tracked origin with `exclude_origin/2` goes back to capturing
    only `nil`.

  This matches Yjs, where `trackedOrigins` defaults to `new Set([null])`, except that
  `nil` cannot be tracked alongside other origins. The manager's own undo and redo
  transactions are always tracked, so undone changes can be redone.

  To track origins from the moment the manager is created, pass them as
  `tracked_origins` in `Yex.UndoManager.Options` instead of calling
  `include_origin/2` afterwards; otherwise a `nil`-origin change made in between
  is captured.

  ## Undo and redo origins

  Undo and redo commit a transaction whose origin is the manager itself. Update
  subscribers (`Yex.Doc.monitor_update/2`) and observers (`Yex.SharedType.observe/2`)
  receive that `%Yex.UndoManager{}` as the origin, so it can be matched against the
  manager in use:

      receive do
        {:update_v1, _update, ^undo_manager, _doc} -> :undo_or_redo
      end

  ## Stack events and meta

  `observe/2` subscribes the calling process to changes of the undo and redo stacks.
  Each captured transaction produces one `Yex.UndoManager.StackItemEvent` (`:added` or
  `:updated`), each undo or redo that changes the document produces an `:added` event
  for the item pushed onto the other stack followed by a `:popped` event, and `clear/1`
  produces a `Yex.UndoManager.StackClearedEvent`. Events for one manager arrive in
  commit order, and they are in the mailbox of a subscriber when the call that caused
  them returns to it.

  Every stack item has an id (`:item`) and a meta term, `nil` until set with
  `put_meta/3`. Applications store state to restore on undo, such as a cursor as a
  `Yex.StickyIndex`, when an item is added, and read it back from the `:popped` event:

      ref = Yex.UndoManager.observe(undo_manager)
      cursor = Yex.StickyIndex.new(text, 0, :after)
      Yex.Text.insert(text, 0, "a")

      receive do
        {:undo_manager_event, ^ref, %Yex.UndoManager.StackItemEvent{type: :added, item: id}, _} ->
          Yex.UndoManager.put_meta(undo_manager, id, cursor)
      end

  Yjs sets meta synchronously inside the event handler. Here the subscriber sets it
  after the event arrives, so:

  * An undo issued before `put_meta/3` runs pops the item without its meta: the
    `:popped` event carries `nil` and `put_meta/3` returns `{:error, :not_found}`. This
    happens when another process issues the undo, and when the subscriber is the
    document's worker and a call delegated to it runs before it handles the event. Set
    meta in the process that issues undo and redo.
  * The state to store is the state before the change, which may have moved on by the
    time the event is handled (for example, a second edit arrived first). Since there
    is exactly one `:added` or `:updated` event per captured transaction, in commit
    order, keep a queue of the state before each edit and take one entry per event.

  Meta lives in the stack item and is freed with it. A meta term that holds the undo
  manager, directly or through another term such as a `Yex.Subscription`, keeps the
  manager alive forever.
  Meta that holds the document, such as a `Yex.StickyIndex`, is freed when the manager
  is, so it does not keep the document alive.

  A subscription keeps its manager alive and capturing until it is removed with
  `unobserve/1` or its process exits.

  Unlike Yjs, dropping the redo stack because of a new change emits no
  `Yex.UndoManager.StackClearedEvent`; `redo_stack_size/1` reports it.
  """
  defstruct [:reference, :doc]

  @type t :: %__MODULE__{
          reference: reference(),
          doc: Yex.Doc.t()
        }

  @doc """
  Creates a new UndoManager for the given document and scope with default options.
  See "Scope" in the module documentation for the accepted scopes.

  ## Errors
  - Returns `{:error, "NIF error: Failed to get branch reference"}` if there's an error
    accessing the scope
  - Raises `Yex.TransactionAcqError` when a transaction on the document is open,
    for example inside `Yex.Doc.transaction/3`
  - Raises `ArgumentError` if `scope` belongs to a document other than `doc`
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
  - Raises `Yex.TransactionAcqError` when a transaction on the document is open,
    for example inside `Yex.Doc.transaction/3`
  - Raises `ArgumentError` if `scope` belongs to a document other than `doc`
  """
  @spec new_with_options(Yex.Doc.t(), struct(), Options.t()) ::
          {:ok, Yex.UndoManager.t()} | {:error, term()}
  def new_with_options(doc, scope, options)
      when is_struct(doc, Yex.Doc) and
             is_valid_scope(scope) and
             is_struct(options, Options) do
    Doc.run_in_worker_process doc do
      ensure_no_transaction!(doc)

      case Yex.Nif.undo_manager_new_with_options(doc, scope, options) do
        {:ok, manager} -> {:ok, manager}
        {:error, message} -> {:error, "NIF error: #{message}"}
      end
    end
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.

  After the first included origin, transactions with a `nil` origin are no longer
  captured. See "Tracked origins" in the module documentation.
  """
  def include_origin(%{doc: doc} = undo_manager, origin) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.undo_manager_include_origin(undo_manager, origin)
    )
  end

  @doc """
  Excludes an origin from being tracked by the UndoManager.

  This removes an origin added with `include_origin/2` or `tracked_origins`. Origins
  that were never included are already not captured, so excluding one has no effect.
  Excluding the last tracked origin makes the manager capture `nil`-origin
  transactions again.
  """
  def exclude_origin(%{doc: doc} = undo_manager, origin) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.undo_manager_exclude_origin(undo_manager, origin)
    )
  end

  @doc """
  Undoes the last tracked change.

  Returns `:ok` whether or not anything was undone; use `undo_with_result/1`
  to learn which. Raises `Yex.TransactionAcqError` when a transaction
  on the document is open (for example when called inside
  `Yex.Doc.transaction/3`), because undo commits a transaction of its own.
  """
  @spec undo(t) :: :ok | {:error, term()}
  def undo(undo_manager), do: discard_result(undo_with_result(undo_manager))

  @doc """
  Undoes the last tracked change and reports whether the document changed.

  Returns `{:ok, false}` when the undo stack is empty. Raises
  `Yex.TransactionAcqError` under the same condition as `undo/1`,
  whether or not the stack is empty.
  """
  @spec undo_with_result(t) :: {:ok, boolean()} | {:error, term()}
  def undo_with_result(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process doc do
      ensure_no_transaction!(doc)
      Yex.Nif.undo_manager_undo(undo_manager)
    end
  end

  @doc """
  Redoes the last undone change.

  Returns `:ok` whether or not anything was redone; use `redo_with_result/1`
  to learn which. Raises `Yex.TransactionAcqError` when a transaction
  on the document is open.
  """
  @spec redo(t) :: :ok | {:error, term()}
  def redo(undo_manager), do: discard_result(redo_with_result(undo_manager))

  @doc """
  Redoes the last undone change and reports whether the document changed.

  Returns `{:ok, false}` when the redo stack is empty. Raises
  `Yex.TransactionAcqError` when a transaction on the document is open,
  whether or not the stack is empty.
  """
  @spec redo_with_result(t) :: {:ok, boolean()} | {:error, term()}
  def redo_with_result(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process doc do
      ensure_no_transaction!(doc)
      Yex.Nif.undo_manager_redo(undo_manager)
    end
  end

  @doc """
  Returns whether the undo stack holds at least one item.
  """
  @spec can_undo?(t) :: boolean()
  def can_undo?(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_can_undo(undo_manager))
  end

  @doc """
  Returns whether the redo stack holds at least one item.
  """
  @spec can_redo?(t) :: boolean()
  def can_redo?(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_can_redo(undo_manager))
  end

  defp discard_result({:ok, _changed}), do: :ok
  defp discard_result(error), do: error

  @doc """
  Expands the scope of the UndoManager to include additional shared types.
  See "Scope" in the module documentation for the accepted scopes.

  Returns `:ok`, or `{:error, message}` such as
  `{:error, "Failed to get text branch reference"}` when the scope cannot be accessed.
  Raises `Yex.TransactionAcqError` when a transaction on the document is open, and
  `ArgumentError` when `scope` belongs to a document other than the manager's.
  """
  def expand_scope(%{doc: doc} = undo_manager, scope)
      when is_valid_scope(scope) or is_struct(scope, Yex.WeakLink) do
    Doc.run_in_worker_process doc do
      ensure_no_transaction!(doc)
      Yex.Nif.undo_manager_expand_scope(undo_manager, scope)
    end
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
  def stop_capturing(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.undo_manager_stop_capturing(undo_manager)
    )
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

  Subscribers from `observe/2` receive a `Yex.UndoManager.StackClearedEvent` when
  either stack held items.

  Raises `Yex.TransactionAcqError` instead of blocking when a write
  transaction on the document is open, for example inside
  `Yex.Doc.transaction/3`.
  """
  @spec clear(t) :: :ok | {:error, term()}
  def clear(%{doc: doc} = undo_manager) do
    Doc.run_in_worker_process doc do
      ensure_no_transaction!(doc)
      Yex.Nif.undo_manager_clear(undo_manager)
    end
  end

  @doc """
  Subscribes the calling process to stack events of the undo manager.

  Messages have the shape:

      {:undo_manager_event, ref, event, metadata}

  where `ref` is the returned reference, `event` is a `Yex.UndoManager.StackItemEvent`
  or a `Yex.UndoManager.StackClearedEvent`, and `metadata` is the `:metadata` option
  (default `nil`). See "Stack events and meta" in the module documentation.

  Can be called inside `Yex.Doc.transaction/3`; the changes of that transaction are
  delivered when it commits.

  ## Options
    * `:metadata` - a term attached to every message of this subscription.
  """
  @spec observe(t, keyword()) :: reference()
  def observe(%__MODULE__{doc: doc} = undo_manager, opts \\ []) do
    ref = make_ref()
    notify_pid = self()

    sub =
      Doc.run_in_worker_process(doc,
        do:
          Yex.Nif.undo_manager_observe(
            undo_manager,
            notify_pid,
            ref,
            Keyword.get(opts, :metadata)
          )
      )

    Yex.Subscription.register(sub, ref)
  end

  @doc """
  Removes a subscription created with `observe/2`. Returns `:ok` also when it was
  already removed.
  """
  @spec unobserve(reference()) :: :ok
  def unobserve(ref), do: Yex.Subscription.unsubscribe(ref)

  @doc """
  Returns the number of items on the undo stack.

  Changes of a transaction that is still open are captured when it commits, so they
  are not counted yet.
  """
  @spec undo_stack_size(t) :: non_neg_integer()
  def undo_stack_size(%__MODULE__{doc: doc} = undo_manager) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_undo_stack_size(undo_manager))
  end

  @doc """
  Returns the number of items on the redo stack.
  """
  @spec redo_stack_size(t) :: non_neg_integer()
  def redo_stack_size(%__MODULE__{doc: doc} = undo_manager) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_redo_stack_size(undo_manager))
  end

  @doc """
  Sets the meta of the stack item `item`, an id from a
  `Yex.UndoManager.StackItemEvent`, replacing the previous value.

  Returns `{:error, :not_found}` when the item is no longer on either stack: it was
  popped, cleared, or dropped from the redo stack by a new change.
  """
  @spec put_meta(t, pos_integer(), term()) :: :ok | {:error, :not_found}
  def put_meta(%__MODULE__{doc: doc} = undo_manager, item, meta) when is_integer(item) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_put_meta(undo_manager, item, meta))
  end

  @doc """
  Returns the meta of the stack item `item`, `nil` when none was set.

  Returns `{:error, :not_found}` under the same conditions as `put_meta/3`.
  """
  @spec get_meta(t, pos_integer()) :: {:ok, term()} | {:error, :not_found}
  def get_meta(%__MODULE__{doc: doc} = undo_manager, item) when is_integer(item) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.undo_manager_get_meta(undo_manager, item))
  end

  # Must be called inside `Doc.run_in_worker_process/2`: the open transaction is
  # stored in the worker process's dictionary by `Yex.Doc.transaction/3`.
  defp ensure_no_transaction!(%Doc{reference: ref}) do
    if Process.get(ref), do: raise(Yex.TransactionAcqError)
    :ok
  end
end
