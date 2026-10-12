defmodule Yex.SharedType do
  @moduledoc """
  The SharedType protocol defines the behavior of shared types in Yex.
  This module provides functionality for observing changes to shared types,
  including arrays, maps, text, and XML nodes.
  """

  @doc """
  Registers a change observer that will be message every time this shared type is modified.

  If the shared type changes, a message is delivered to the
  monitoring process in the shape of:
      {:observe_event, ref, event, origin, metadata}

  where:
    * `ref` is a monitor reference returned by this function;
    * `event` is a struct that describes the change;
    * `origin` is the origin passed to the `Yex.Doc.transaction()` function, `nil` when
      none was given, or the `%Yex.UndoManager{}` for an undo or redo.
    * `metadata` is the metadata passed to the `observe` function.

  ## Options
    * `:metadata` - provides metadata to be attached to this observe.

  ## Returns
    * A reference that can be used to unsubscribe the observer
  """

  alias Yex.Doc
  require Yex.Doc
  import Yex.Doc, only: [cur_txn: 1]

  @type t ::
          %Yex.Array{}
          | %Yex.Map{}
          | %Yex.Text{}
          | %Yex.XmlElement{}
          | %Yex.XmlText{}
          | %Yex.XmlFragment{}
          | %Yex.WeakLink{}

  @typedoc """
  Logical identifier of a shared type, the same on every replica of a document.

  `{:root, name}` names a root type. `{:nested, client, clock}` names a type nested inside
  another by the ID of the item that created it. Both are plain terms, so they can be stored,
  for example with `:erlang.term_to_binary/1`.
  """
  @type branch_id ::
          {:root, String.t()}
          | {:nested, client :: 0..9_007_199_254_740_991, clock :: 0..4_294_967_295}

  @spec observe(t, keyword()) :: reference()
  def observe(%{doc: doc} = shared_type, opt \\ []) do
    ref = make_ref()
    notify_pid = self()

    sub =
      Doc.run_in_worker_process(doc,
        do:
          Yex.Nif.shared_type_observe(
            shared_type,
            cur_txn(shared_type),
            notify_pid,
            ref,
            Keyword.get(opt, :metadata)
          )
      )

    Yex.Subscription.register(sub, ref)
  end

  @doc """
  Unobserve the shared type for changes.
  Removes the observer registered with the given reference.
  """
  @spec unobserve(reference()) :: :ok
  def unobserve(observe_ref) do
    unsubscribe(observe_ref)
  end

  @doc """
  Registers a change observer that will be message every time this shared type or any of its children is modified.

  If the shared type changes, a message is delivered to the
  monitoring process in the shape of:
      {:observe_deep_event, ref, events, origin, metadata}

  where:
    * `ref` is a monitor reference returned by this function;
    * `events` is a list of structs that describes the changes;
    * `origin` is the origin passed to the `Yex.Doc.transaction()` function, `nil` when
      none was given, or the `%Yex.UndoManager{}` for an undo or redo.
    * `metadata` is the metadata passed to the `observe_deep` function.

  ## Options
    * `:metadata` - provides metadata to be attached to this observe.

  ## Returns
    * A reference that can be used to unsubscribe the deep observer
  """
  @spec observe_deep(t, keyword()) :: reference()
  def observe_deep(%{doc: doc} = shared_type, opt \\ []) do
    ref = make_ref()
    notify_pid = self()

    sub =
      Doc.run_in_worker_process(doc,
        do:
          Yex.Nif.shared_type_observe_deep(
            shared_type,
            cur_txn(shared_type),
            notify_pid,
            ref,
            Keyword.get(opt, :metadata)
          )
      )

    Yex.Subscription.register(sub, ref)
  end

  @doc """
  Unobserve the shared type and its children for changes.
  Removes the deep observer registered with the given reference.
  """
  @spec unobserve_deep(reference()) :: :ok
  def unobserve_deep(observe_ref) do
    unsubscribe(observe_ref)
  end

  @doc """
  Returns the logical identifier of `shared_type`.

  The identifier is read from the struct itself, so this works on a deleted type and does not
  go through the document's worker process.

  ## Examples

      iex> doc = Yex.Doc.new()
      iex> Yex.SharedType.branch_id(Yex.Doc.get_text(doc, "text"))
      {:root, "text"}
  """
  @spec branch_id(t) :: branch_id
  def branch_id(%{doc: %Doc{}} = shared_type), do: Yex.Nif.shared_type_branch_id(shared_type)

  @doc """
  Returns `true` while `shared_type` can still be used.

  A root type is always alive. A nested type stops being alive once it or any of its ancestors
  is deleted, locally or by a remote update; from then on operations on it raise
  `Yex.DeletedSharedTypeError`. Joins an open `Yex.Doc.transaction/3`, so a deletion made
  earlier in the same transaction is seen.

  ## Examples

      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> nested = Yex.Map.set_and_get(map, "nested", Yex.MapPrelim.from(%{}))
      iex> Yex.SharedType.alive?(nested)
      true
      iex> Yex.Map.delete(map, "nested")
      iex> Yex.SharedType.alive?(nested)
      false
  """
  @spec alive?(t) :: boolean()
  def alive?(%{doc: %Doc{} = doc} = shared_type) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.shared_type_alive(shared_type, cur_txn(shared_type))
    )
  end

  @doc """
  Finds the shared type that `branch_id` names in `doc`.

  Returns the typed struct, such as `%Yex.Map{}` or `%Yex.Text{}`. It never creates a type.
  Joins an open `Yex.Doc.transaction/3`.

  Ids are scoped to the document that produced them and its replicas.

  ## Errors

    * `:not_found` - `doc` has no such type: a root that was never created, or a nested type
      whose update `doc` has not integrated yet (including one still pending on a missing
      predecessor). It is not always transient: a nested type that `doc` integrated while an
      earlier range of the same client was still missing, and that was then deleted and
      garbage collected, stays `:not_found` until the missing range arrives.
    * `:deleted` - `doc` has integrated the id and no live shared type is there: the type was
      deleted, or the id names other content. A document sharing the client id with the one
      that produced the id may answer `:deleted` for a foreign id.
    * `:untyped` - a root that only a remote update created and nothing has claimed yet. Claim
      it with the getter for its kind, such as `Yex.Doc.get_map/2`, and resolve again.

  Raises `ArgumentError` for a malformed id: another shape, a name that is not UTF-8, a
  client of 2^53 or more, or a clock of 2^32 or more.

  ## Examples

      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> {:ok, ^text} = Yex.SharedType.resolve(doc, {:root, "text"})
      iex> Yex.SharedType.resolve(doc, {:root, "missing"})
      {:error, :not_found}
  """
  @spec resolve(Doc.t(), branch_id) :: {:ok, t} | {:error, :not_found | :deleted | :untyped}
  def resolve(%Doc{} = doc, branch_id) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.shared_type_resolve(doc, cur_txn(doc), branch_id)
    )
  end

  @doc false
  # Unsubscribes an observer using the Yex.Subscription module
  defp unsubscribe(ref) do
    Yex.Subscription.unsubscribe(ref)
  end
end

defprotocol Yex.Output do
  @moduledoc """
  Protocol for converting shared types to their preliminary representations.
  This is useful for serialization and data transfer between different parts of the system.
  """

  @fallback_to_any true

  @doc """
  Converts a shared type to its preliminary representation.
  The preliminary representation is a simpler form that can be easily serialized or transferred.
  """
  def as_prelim(shared_type)
end

defimpl Yex.Output, for: Any do
  @doc """
  Default implementation for types that don't need conversion.
  Returns the shared type as is.
  """
  def as_prelim(shared_type), do: shared_type
end

defmodule Yex.PrelimType do
  @moduledoc """
  A type that represents preliminary data structures used in Yex.
  This is used to represent data that can be serialized or transferred without the full shared type overhead.
  """
  @type t ::
          Yex.MapPrelim.t()
          | Yex.TextPrelim.t()
          | Yex.WeakPrelim.t()
          | Yex.ArrayPrelim.t()
          | Yex.XmlElementPrelim.t()
          | Yex.XmlFragmentPrelim.t()
          | Yex.XmlTextPrelim.t()
end
