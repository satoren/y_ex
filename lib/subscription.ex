defmodule Yex.Subscription do
  @moduledoc """
  Provides subscription functionality for monitoring changes in shared types.
  This module implements features for observing changes in documents and other shared types,
  and receiving notifications when changes occur.

  ## Features
  - Monitor change events in shared types
  - Process-level subscription management
  - Prevention of automatic resource release
  - Simple unsubscribe functionality

  ## Usage
  Subscriptions are typically created by monitoring functions like `Yex.Doc.monitor_update/2`
  or `Yex.SharedType.observe/2` and are used to receive change notifications:

      iex> doc = Yex.Doc.new()
      iex> {:ok, ref} = Yex.Doc.monitor_update(doc)
      iex> # Monitor changes...
      iex> Yex.Subscription.unsubscribe(ref) # Unsubscribe from monitoring
      :ok
  """

  defstruct [
    :reference,
    :doc
  ]

  alias Yex.Doc
  require Yex.Doc

  @type t :: %__MODULE__{
          reference: reference(),
          doc: Yex.Doc.t()
        }

  @doc """
  Registers a subscription and returns a reference.
  This function stores the subscription in the process dictionary to prevent
  automatic release by the garbage collector.

  ## Parameters
    * `sub` - The subscription to register
    * `ref` - Optional reference. If not provided, a new reference will be generated

  ## Returns
    * The subscription reference
  """
  def register(%__MODULE__{} = sub, ref \\ make_ref()) do
    # Subscription should not be automatically released by gc, so put it in the process dictionary
    Process.put(ref, sub)
    ref
  end

  @doc """
  Unsubscribes from a subscription.
  Removes the subscription associated with the given reference from the
  process dictionary and cleans up resources.

  ## Parameters
    * `ref` - The reference of the subscription to unsubscribe

  ## Returns
    * `:ok` - If unsubscription was successful
  """
  def unsubscribe(ref) do
    case Process.get(ref) do
      %__MODULE__{doc: doc} = sub ->
        Process.delete(ref)

        Doc.run_in_worker_process doc do
          Yex.Nif.sub_unsubscribe(sub)
        end

      _ ->
        :ok
    end
  end
end
