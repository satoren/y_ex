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
    * `origin` is the origin passed to the `Yex.Doc.transaction()` function.
    * `metadata` is the metadata passed to the `observe` function.

  ## Options
    * `:metadata` - provides metadata to be attached to this observe.

  ## Returns
    * A reference that can be used to unsubscribe the observer
  """

  alias Yex.Doc
  require Yex.Doc

  @type t ::
          %Yex.Array{}
          | %Yex.Map{}
          | %Yex.Text{}
          | %Yex.XmlElement{}
          | %Yex.XmlText{}
          | %Yex.XmlFragment{}

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
    * `origin` is the origin passed to the `Yex.Doc.transaction()` function.
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

  @doc false
  # Gets the current transaction reference from the process dictionary
  defp cur_txn(%{doc: doc_ref}) do
    Process.get(doc_ref, nil)
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
