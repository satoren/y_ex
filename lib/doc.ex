defmodule Yex.Doc do
  @moduledoc """
  Document module.


  ### Cross-Process Operations
    When a Doc or SharedType operation is performed from a process different from the process that created the Doc,
    a message like `{Yex.Doc, :run, fun}` is sent to the creator process via `GenServer.call` and the processing
    is delegated to that process. If you encounter a `GenServer.call` timeout, this delegation mechanism may be the cause.
    Make sure the worker process can handle the GenServer call messages properly.

    It is recommended to start a GenServer process such as `Yex.DocServer` when executing operations from other processes.

    A subdocument can be reachable from two worker processes: the process that created it with `new/1`
    and the parent's worker, which hands it out from the parent. `destroy/1` and `load/1` check that
    the documents they lock are free and raise `Yex.TransactionAcqError` otherwise, but if the other
    worker takes one of those locks right after that check, they block until it is released, and
    they deadlock if that process then calls into this worker (for example a write to the parent
    from inside its open transaction on the subdocument).
  """

  defmodule Options do
    @moduledoc """
    Document options.

    `client_id` defaults to `nil`, which picks a random client id in
    `0..9007199254740991`, the same as `Yex.Doc.new/0`. Collaborating replicas
    must not share a client id.

    > #### Breaking change {: .warning}
    >
    > Up to 0.12.1 `client_id` defaulted to `0`, so every document built from
    > these options, including every `Yex.DocServer` started with a
    > `:doc_option`, wrote its items under client `0`. Code that seeds content
    > on start (for example in `c:Yex.DocServer.init/2`) wrote the same item
    > ids on every restart, and peers holding the old state deduplicated them.
    > With a random client id each restart writes the seed under a new client,
    > and those peers see the seeded content twice. Pass an explicit
    > `client_id` to keep the old behaviour.
    """
    defstruct client_id: nil,
              guid: nil,
              collection_id: nil,
              offset_kind: :bytes,
              skip_gc: false,
              auto_load: false,
              should_load: true

    @type t :: %__MODULE__{
            client_id: non_neg_integer() | nil,
            guid: String.t() | nil,
            collection_id: String.t(),
            offset_kind: :bytes | :utf16,
            skip_gc: boolean(),
            auto_load: boolean(),
            should_load: boolean()
          }
  end

  defstruct [
    :reference,
    worker_pid: nil
  ]

  @type t :: %__MODULE__{
          reference: any(),
          worker_pid: pid() | nil
        }

  @doc """
  Executes the given block in the document's worker process.
  If the current process is already the worker process, executes directly.
  Otherwise, delegates execution to the worker process via GenServer.call.

  Raises if worker_pid is not set.
  """
  defmacro run_in_worker_process(doc, do: block) do
    quote do
      case unquote(doc).worker_pid do
        pid when pid == self() ->
          unquote(block)

        nil ->
          raise RuntimeError, "Document has no worker process assigned"

        worker_pid ->
          wrapped_fun = fn ->
            try do
              unquote(block)
            rescue
              e ->
                {Yex.Doc, :reraise, e, __STACKTRACE__}
            end
          end

          # When a Doc or SharedType operation is performed from a process different from the
          # process that created the Doc, a message like {Yex.Doc, :run, fun} is sent to the
          # creator process via GenServer.call and the processing is delegated to that process.
          # If you encounter a GenServer.call timeout, this delegation mechanism may be the cause.
          case GenServer.call(
                 worker_pid,
                 {Yex.Doc, :run, wrapped_fun}
               ) do
            {Yex.Doc, :reraise, e, stacktrace} ->
              reraise e, stacktrace

            result ->
              result
          end
      end
    end
  end

  @doc """
  Create a new document.

  worker_pid:
     If there is a possibility of passing the created document to another process, please specify the process responsible for operating the document.
     This process needs to handle the GenServer handle_call messages as follows:

      @impl true
      def handle_call(
            {Yex.Doc, :run, fun},
            _from,
            state
          ) do
        {:reply, fun.(), state}
      end
  """
  @spec new(pid()) :: Yex.Doc.t()
  def new(worker_pid \\ self()) do
    Yex.Nif.doc_new() |> Map.put(:worker_pid, worker_pid)
  end

  @doc """
  Create a new document with options.

  A random client id is used when `client_id` is `nil` (the default).

  Raises `ArgumentError` when `client_id` is outside `0..9007199254740991`
  (`2^53 - 1`), the range of yjs client ids.
  """
  @spec with_options(Options.t(), pid()) :: Yex.Doc.t()
  def with_options(%Options{} = option, worker_pid \\ self()) do
    Yex.Nif.doc_with_options(option) |> Map.put(:worker_pid, worker_pid)
  end

  @doc """
  Returns the client ID of the document.

  The client ID uniquely identifies this replica when generating updates.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10})
      iex> Yex.Doc.client_id(doc)
      10
  """
  @spec client_id(t) :: integer()
  def client_id(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_client_id(doc))
  end

  @doc """
  Returns the globally unique identifier of the document.

  A random GUID is generated when none was given in `Yex.Doc.Options`.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{guid: "my-guid"})
      iex> Yex.Doc.guid(doc)
      "my-guid"
  """
  @spec guid(t) :: String.t()
  def guid(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_guid(doc))
  end

  @doc """
  Returns the collection ID of the document, or an empty string when none was set.
  """
  @spec collection_id(t) :: String.t()
  def collection_id(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_collection_id(doc))
  end

  @doc """
  Returns whether garbage collection of deleted content is disabled for the document.
  """
  @spec skip_gc(t) :: boolean()
  def skip_gc(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_skip_gc(doc))
  end

  @doc """
  Returns whether the document, when used as a subdocument, is loaded automatically.
  """
  @spec auto_load(t) :: boolean()
  def auto_load(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_auto_load(doc))
  end

  @doc """
  Returns whether the document, when used as a subdocument, should be loaded by the provider.
  """
  @spec should_load(t) :: boolean()
  def should_load(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_should_load(doc))
  end

  @doc """
  Returns how text offsets are measured: `:bytes` (UTF-8 bytes) or `:utf16` (UTF-16 code units).
  """
  @spec offset_kind(t) :: :bytes | :utf16
  def offset_kind(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_offset_kind(doc))
  end

  @doc """
  Get or insert the text type.
  """
  @spec get_text(t, String.t()) :: Yex.Text.t()
  def get_text(%__MODULE__{} = doc, name) do
    run_in_worker_process(doc, do: Yex.Nif.doc_get_or_insert_text(doc, cur_txn(doc), name))
  end

  @doc """
  Get or insert the array type.
  """
  @spec get_array(t, String.t()) :: Yex.Array.t()
  def get_array(%__MODULE__{} = doc, name) do
    run_in_worker_process(doc, do: Yex.Nif.doc_get_or_insert_array(doc, cur_txn(doc), name))
  end

  @doc """
  Get or insert the map type.
  """
  @spec get_map(t, String.t()) :: Yex.Map.t()
  def get_map(%__MODULE__{} = doc, name) do
    run_in_worker_process(doc, do: Yex.Nif.doc_get_or_insert_map(doc, cur_txn(doc), name))
  end

  @doc """
  Get or insert the xml fragment type.
  """
  def get_xml_fragment(%__MODULE__{} = doc, name) do
    run_in_worker_process(doc,
      do: Yex.Nif.doc_get_or_insert_xml_fragment(doc, cur_txn(doc), name)
    )
  end

  @doc """
  Lists every root type the document holds as `{name, kind}`. Order is unspecified.

  A root claimed by a typed getter reports its declared type: `:map`, `:array`,
  `:text` or `:xml_fragment`. `:xml_element`, `:xml_text` and `:weak_link` cover the
  remaining yrs types that can be a root.

  A root no typed getter has claimed reports `:untyped`, whatever it holds. Every
  root a remote update created starts this way, and keeps it until something calls
  a typed getter with its name. The kind is not guessed from content: an XML
  fragment and an array of XML nodes, or a text and an array of strings, can hold
  the same items.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> Yex.Doc.get_text(doc, "text")
      iex> Yex.Doc.root_refs(doc)
      [{"text", :text}]
  """
  @spec root_refs(t) :: [
          {String.t(),
           :map
           | :array
           | :text
           | :xml_fragment
           | :xml_element
           | :xml_text
           | :weak_link
           | :untyped}
        ]
  def root_refs(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_root_refs(doc, cur_txn(doc)))
  end

  @doc """
  Evaluates a JSONPath expression against the current document state.

  Returns all matched values as a list. The path grammar follows yrs JSONPath
  support (for example: `$.users[*].name`, `$.users..nick`).
  """
  @spec json_path(t, binary()) :: {:ok, list()} | {:error, term()}
  def json_path(%__MODULE__{} = doc, path) when is_binary(path) do
    run_in_worker_process doc do
      Yex.Nif.transaction_json_path_all(doc, cur_txn(doc), path)
    end
  end

  @doc """
  Returns the pending update (v1 encoded) for the document, if any.

  A pending update accumulates operations that arrived out of order and
  could not yet be applied because their causal predecessors are missing.
  Returns `{:ok, binary()}` when a pending update exists, `{:ok, nil}` otherwise.
  """
  @spec get_pending_update(t) :: {:ok, binary() | nil} | {:error, term()}
  def get_pending_update(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.get_pending_update_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Returns the pending delete set (v1 encoded) for the document, if any.

  A pending delete set holds deletions that arrived out of order and could
  not yet be applied. Returns `{:ok, binary()}` when a pending delete set
  exists, `{:ok, nil}` otherwise.
  """
  @spec get_pending_ds(t) :: {:ok, binary() | nil} | {:error, term()}
  def get_pending_ds(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.get_pending_ds_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Removes and returns the pending update and pending delete set (v1 encoded,
  merged into one update) for the document, if any.

  Pending state holds structs and deletions that arrived before their causal
  predecessors and are waiting on them. After this returns, both
  `get_pending_update/1` and `get_pending_ds/1` return `{:ok, nil}`, and the
  pruned content will no longer be integrated when the missing predecessors
  arrive. The returned binary can be re-applied later, for example once the
  missing updates have been fetched.

  Works both inside and outside `transaction/3`. Returns `{:ok, nil}` when
  nothing is pending. Raises `Yex.TransactionAcqError` when a
  transaction held by another process prevents opening one.
  """
  @spec prune_pending(t) :: {:ok, binary() | nil} | {:error, term()}
  def prune_pending(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.prune_pending_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Garbage-collects deleted content now, even when the document was created with
  `skip_gc: true`.

  Deleted items are replaced by lightweight placeholders, so their content can no
  longer be restored (for example from a snapshot taken before the deletion).
  Content kept on an `Yex.UndoManager`'s stacks is not collected. Works both inside
  and outside `transaction/3`.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "Hello World")
      iex> Yex.Text.delete(text, 0, 6)
      iex> Yex.Doc.force_gc(doc)
      :ok
      iex> Yex.Text.to_string(text)
      "World"
  """
  @spec force_gc(t) :: :ok
  def force_gc(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.doc_force_gc(doc, cur_txn(doc))
    end
  end

  @doc """
  Requests a subdocument to be loaded.

  Sets `should_load/1` to `true`. When the document is a subdocument, its parent
  emits a subdocs event listing it under `:loaded` (see `monitor_subdocs/2`), which
  providers use to start syncing it.

  Raises `Yex.TransactionAcqError` when called inside a transaction on the
  document or its parent.
  """
  @spec load(t) :: :ok
  def load(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.doc_load(doc)
    end
  end

  @doc """
  Destroys the document, dropping all of its observers and destroying its subdocuments.

  When the document is a subdocument, its parent replaces it with a new, unloaded
  document with the same guid, and emits a subdocs event listing it under
  `:removed` and `:added`. Getting the subdocument from the parent again returns
  that new document. Use this to free a loaded subdocument.

  Sends `{:destroy, metadata}` to the `monitor_destroy/2` subscribers, then drops the
  document-level subscriptions (`monitor_update/2`, `monitor_update_v2/2`,
  `monitor_subdocs/2`, `monitor_transaction_cleanup/2`, `monitor_destroy/2`).
  `Yex.SharedType.observe/2` and `Yex.SharedType.observe_deep/2` subscriptions stay,
  and the document stays usable.

  With yrs 0.28 the doc listed under `:added` is not the live replacement: yrs reports
  the replacement as removed and then destroys it too, and `subdocs/1` on the parent
  still lists the destroyed doc. Fetch the replacement from the container instead.
  Until yrs changes this, destroying the parent later does not destroy that
  replacement, and calling `subdocs/1` on the parent replaces the cached resource for
  that guid.

  Raises `Yex.TransactionAcqError` when called inside a transaction on the
  document, one of its subdocuments or its parent.
  """
  @spec destroy(t) :: :ok
  def destroy(%__MODULE__{} = doc) do
    run_in_worker_process doc do
      Yex.Nif.doc_destroy(doc)
    end
  end

  @doc """
  Start a transaction.

  Raises `Yex.TransactionAcqError` if a transaction is already in progress.

  The transaction is committed when `exec` returns and also when it raises, throws or
  exits, like `transact` in yjs: changes made before the error are kept, their events
  are emitted, and then the error propagates. There is no rollback.

  If the process running `exec` is killed, the transaction is committed when its
  resource is freed. That commit keeps the changes and releases the document, but
  its events cannot be delivered and are dropped.

  ## Examples
      iex> doc = Doc.new()
      iex> text = Doc.get_text(doc, "text")
      iex> Yex.Doc.monitor_update(doc)
      iex> Doc.transaction(doc, fn ->
      iex>   Text.insert(text, 0, "Hello")
      iex>   Text.insert(text, 0, "Hello", %{"bold" => true})
      iex> end)
      iex> assert_receive {:update_v1, _, nil, _}
      iex> refute_receive {:update_v1, _, nil, _}, 10 # only one update message

  """
  @spec transaction(t, origin :: term(), fun()) :: term()
  def transaction(%__MODULE__{reference: ref} = doc, origin \\ nil, exec) do
    run_in_worker_process doc do
      if cur_txn(doc) do
        raise Yex.TransactionAcqError
      end

      txn = Yex.Nif.doc_begin_transaction(doc, origin)

      try do
        Process.put(ref, txn)
        exec.()
      after
        Process.delete(ref)
        Yex.Nif.commit_transaction(txn)
      end
    end
  end

  @doc """
  Monitor document updates.
   You can pass metadata as an option. This value is passed as the fourth element of the message.If omitted, it will be passed as a structure of Doc itself.

  The third element is the transaction's origin: the term passed to `transaction/3`,
  `nil` when none was given, or the `%Yex.UndoManager{}` for a transaction committed
  by `Yex.UndoManager.undo/1` or `Yex.UndoManager.redo/1`.

  Works inside `transaction/3`; that transaction is reported when it commits.
  """
  @spec monitor_update(t, keyword) :: {:ok, reference()} | {:error, term()}
  def monitor_update(%__MODULE__{} = doc, opt \\ []) do
    monitor_update_v1(doc, opt)
  end

  @doc """
  Monitor document updates encoded with the v1 format.

  The calling process receives `{:update_v1, update, origin, metadata}` messages.
  See `monitor_update/2` for the meaning of `origin`, the `:metadata` option and use
  inside `transaction/3`.
  """
  @spec monitor_update_v1(t, keyword) :: {:ok, reference()} | {:error, term()}
  def monitor_update_v1(%__MODULE__{} = doc, opt \\ []) do
    notify_pid = self()

    case run_in_worker_process(doc,
           do:
             Yex.Nif.doc_monitor_update_v1(
               doc,
               cur_txn(doc),
               notify_pid,
               Keyword.get(opt, :metadata, doc)
             )
         ) do
      {:ok, sub} ->
        {:ok, Yex.Subscription.register(sub)}

      error ->
        error
    end
  end

  @doc """
  Monitor document updates encoded with the v2 format.

  The calling process receives `{:update_v2, update, origin, metadata}` messages.
  See `monitor_update/2` for the meaning of `origin`, the `:metadata` option and use
  inside `transaction/3`.
  """
  @spec monitor_update_v2(t, keyword) :: {:ok, reference()} | {:error, term()}
  def monitor_update_v2(%__MODULE__{} = doc, opt \\ []) do
    notify_pid = self()

    case run_in_worker_process(doc,
           do:
             Yex.Nif.doc_monitor_update_v2(
               doc,
               cur_txn(doc),
               notify_pid,
               Keyword.get(opt, :metadata, doc)
             )
         ) do
      {:ok, sub} ->
        {:ok, Yex.Subscription.register(sub)}

      error ->
        error
    end
  end

  @doc """
  Stop monitoring document updates.
  """
  @spec demonitor_update(reference()) :: :ok | {:error, term()}
  def demonitor_update(sub) do
    demonitor_update_v1(sub)
  end

  @doc """
  Stop monitoring document updates started with `monitor_update_v1/2`.
  """
  @spec demonitor_update_v1(reference()) :: :ok | {:error, term()}
  def demonitor_update_v1(sub) do
    Yex.Subscription.unsubscribe(sub)
  end

  @doc """
  Stop monitoring document updates started with `monitor_update_v2/2`.
  """
  @spec demonitor_update_v2(reference()) :: :ok | {:error, term()}
  def demonitor_update_v2(sub) do
    Yex.Subscription.unsubscribe(sub)
  end

  @doc """
  Monitor subdocument changes.

  The calling process receives
  `{:subdocs, %{added: [Yex.Doc.t()], removed: [Yex.Doc.t()], loaded: [Yex.Doc.t()]}, origin, metadata}`
  messages whenever subdocuments are added to, removed from, or loaded in this document.
  You can pass metadata as an option; if omitted, the document itself is used.
  Works inside `transaction/3`; that transaction is reported when it commits.

  Use `Yex.Subscription.unsubscribe/1` with the returned reference to stop monitoring.
  """
  @spec monitor_subdocs(t, keyword) :: {:ok, reference()} | {:error, term()}
  def monitor_subdocs(%__MODULE__{} = doc, opt \\ []) do
    notify_pid = self()

    case run_in_worker_process(doc,
           do:
             Yex.Nif.doc_monitor_subdocs(
               doc,
               cur_txn(doc),
               notify_pid,
               Keyword.get(opt, :metadata, doc)
             )
         ) do
      {:ok, sub} ->
        {:ok, Yex.Subscription.register(sub)}

      error ->
        error
    end
  end

  @doc """
  Monitor committed transactions.

  The calling process receives
  `{:transaction_cleanup, %Yex.TransactionCleanupEvent{}, origin, metadata}` after every
  committed transaction that changed the document, local or remote. The event carries the
  document's state vector before and after the transaction and the ids it deleted; see
  `Yex.TransactionCleanupEvent`. This is yjs's `afterTransactionCleanup` event.

  Transactions that changed nothing are not reported. yjs reports every transaction, but
  y_ex also opens empty write transactions internally (for example in `get_text/2` and
  when subscribing), which would show up as noise. This includes a remote update that
  only adds structs waiting on missing predecessors: they are held as pending (see
  `get_pending_update/1`) and change neither the state vector nor the delete set until
  they integrate.

  `origin` and the `:metadata` option work as in `monitor_update/2`. Works inside
  `transaction/3`; that transaction is reported when it commits.

  Use `Yex.Subscription.unsubscribe/1` with the returned reference to stop monitoring.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1})
      iex> {:ok, _ref} = Yex.Doc.monitor_transaction_cleanup(doc)
      iex> Yex.Text.insert(Yex.Doc.get_text(doc, "text"), 0, "Hello")
      iex> assert_receive {:transaction_cleanup, event, nil, ^doc}
      iex> {event.before_state, event.after_state, event.delete_set}
      {%{}, %{1 => 5}, %{}}
  """
  @spec monitor_transaction_cleanup(t, keyword) :: {:ok, reference()}
  def monitor_transaction_cleanup(%__MODULE__{} = doc, opt \\ []) do
    notify_pid = self()

    {:ok, sub} =
      run_in_worker_process(doc,
        do:
          Yex.Nif.doc_monitor_transaction_cleanup(
            doc,
            cur_txn(doc),
            notify_pid,
            Keyword.get(opt, :metadata, doc)
          )
      )

    {:ok, Yex.Subscription.register(sub)}
  end

  @doc """
  Monitor destruction of the document.

  The calling process receives `{:destroy, metadata}` when `destroy/1` is called on this
  document, on a document containing it, or when the document is removed from its parent
  document. `metadata` defaults to the document itself. Works inside `transaction/3`.

  Use `Yex.Subscription.unsubscribe/1` with the returned reference to stop monitoring.
  """
  @spec monitor_destroy(t, keyword) :: {:ok, reference()}
  def monitor_destroy(%__MODULE__{} = doc, opt \\ []) do
    notify_pid = self()

    {:ok, sub} =
      run_in_worker_process(doc,
        do:
          Yex.Nif.doc_monitor_destroy(
            doc,
            cur_txn(doc),
            notify_pid,
            Keyword.get(opt, :metadata, doc)
          )
      )

    {:ok, Yex.Subscription.register(sub)}
  end

  @doc """
  Returns the subdocuments linked in the document, in no particular order
  (yjs `getSubdocs()`).

  A subdocument inserted in an open `transaction/3` is listed once that transaction
  commits.

  This call is not free of side effects. After a subdocument was destroyed, yrs 0.28
  leaves the parent listing the destroyed doc (see `destroy/1`). Listing it caches that
  doc under its guid in place of the live replacement, so the next lookup of the
  replacement through its container (`Yex.Map.fetch/2`, say) returns a new resource
  whose `reference` differs from one fetched before this call.
  """
  @spec subdocs(t) :: [t]
  def subdocs(%__MODULE__{} = doc) do
    run_in_worker_process(doc, do: Yex.Nif.doc_subdocs(doc, cur_txn(doc)))
  end

  @doc false
  # Returns the transaction opened by `transaction/3` in the calling process, or nil.
  # Accepts a doc or any struct holding one in its `:doc` field (shared types, sticky indexes).
  def cur_txn(%__MODULE__{reference: ref}), do: Process.get(ref, nil)
  def cur_txn(%{doc: %__MODULE__{} = doc}), do: cur_txn(doc)
end

defmodule Yex.TransactionCleanupEvent do
  @moduledoc """
  A committed transaction, as sent by `Yex.Doc.monitor_transaction_cleanup/2`.

    * `before_state` - the document's state vector when the transaction started.
    * `after_state` - the document's state vector after it committed.
    * `delete_set` - the ids deleted by the transaction.
  """
  defstruct [:before_state, :after_state, :delete_set]

  @type t :: %__MODULE__{
          before_state: Yex.state_vector(),
          after_state: Yex.state_vector(),
          delete_set: Yex.delete_set()
        }
end
