defmodule Yex.SharedType do
  @moduledoc """
  The SharedType protocol defines the behavior of shared types in Yex.

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

    sub =
      Doc.run_in_worker_process(doc,
        do:
          Yex.Nif.shared_type_observe(
            shared_type,
            cur_txn(shared_type),
            self(),
            ref,
            Keyword.get(opt, :metadata)
          )
      )

    Yex.Subscription.register(sub, ref)
  end

  @doc """
  Unobserve the shared type for changes.

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
    * `events` is a array of event struct that describes the change;
    * `origin` is the origin passed to the `Yex.Doc.transaction()` function.
    * `metadata` is the metadata passed to the `observe_deep` function.

  ## Options
    * `:metadata` - provides metadata to be attached to this observe.

  """
  @spec observe_deep(t, keyword()) :: reference()
  def observe_deep(%{doc: doc} = shared_type, opt \\ []) do
    ref = make_ref()

    sub =
      Doc.run_in_worker_process(doc,
        do:
          Yex.Nif.shared_type_observe_deep(
            shared_type,
            cur_txn(shared_type),
            self(),
            ref,
            Keyword.get(opt, :metadata)
          )
      )

    Yex.Subscription.register(sub, ref)
  end

  @doc """
  Unobserve the shared type for changes.

  """
  @spec unobserve_deep(reference()) :: :ok
  def unobserve_deep(observe_ref) do
    unsubscribe(observe_ref)
  end

  defp cur_txn(%{doc: doc_ref}) do
    Process.get(doc_ref, nil)
  end

  defp unsubscribe(ref) do
    Yex.Subscription.unsubscribe(ref)
  end
end

defprotocol Yex.Output do
  @fallback_to_any true
  def as_prelim(shared_type)
end

defimpl Yex.Output, for: Any do
  def as_prelim(shared_type), do: shared_type
end
