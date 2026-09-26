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
  """
  defstruct [:reference, :doc]

  @type t :: %__MODULE__{
          reference: reference(),
          doc: Yex.Doc.t()
        }

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
  - Raises `Yex.TransactionAcqError` when a transaction on the document is open,
    for example inside `Yex.Doc.transaction/3`
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
  The scope can be a Text, Array, or Map type.

  Raises `Yex.TransactionAcqError` when a transaction on the document is open.
  """
  def expand_scope(%{doc: doc} = undo_manager, scope) do
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

  # Must be called inside `Doc.run_in_worker_process/2`: the open transaction is
  # stored in the worker process's dictionary by `Yex.Doc.transaction/3`.
  defp ensure_no_transaction!(%Doc{reference: ref}) do
    if Process.get(ref), do: raise(Yex.TransactionAcqError)
    :ok
  end
end
