defmodule Yex.Awareness do
  @moduledoc """


  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _awareness} = Yex.Awareness.new(doc)
  """

  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  def new(doc), do: Yex.Nif.awareness_new(doc)

  # crdt api

  @spec client_id(t) :: integer()
  def client_id(%__MODULE__{} = awareness), do: Yex.Nif.awareness_client_id(awareness)
  def get_local_state(%__MODULE__{} = awareness), do: Yex.Nif.awareness_get_local_state(awareness)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.get_states(awareness)
      %{100 => %{"key" => "value"}}
  """
  def set_local_state(%__MODULE__{} = awareness, map),
    do: Yex.Nif.awareness_set_local_state(awareness, map)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.clean_local_state(awareness)
      iex> Yex.Awareness.get_client_ids(awareness)
      []
  """
  def clean_local_state(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_clean_local_state(awareness)

  @doc """


  ## Examples
  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      iex> Yex.Awareness.get_client_ids(awareness)
      [2230489810]
  """
  def get_client_ids(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_get_client_ids(awareness)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.get_states(awareness)
      %{100 => %{"key" => "value"}}
  """
  def get_states(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_get_states(awareness)

  @doc """
   Monitor to remote and local awareness changes. This event is called even when the awareness state does not change but is only updated to notify other users that this client is still online. Use this event if you want to propagate awareness state to other users.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.monitor_update(awareness)
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> receive do {:awareness_update, %{removed: [], added: [10], updated: []}, _origin, _awareness} -> :ok end
  """
  def monitor_update(%__MODULE__{} = awareness) do
    case Yex.Nif.awareness_monitor_update(awareness, self()) do
      {:ok, ref} ->
        # Subscription should not be automatically released by gc, so put it in the process dictionary
        Process.put(__MODULE__.Subscriptions, [ref | Process.get(__MODULE__.Subscriptions, [])])
        {:ok, ref}

      error ->
        error
    end
  end

  def demonitor_update(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end

  @doc """
   Listen to remote and local state changes. Get notified when a state is either added, updated, or removed.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.monitor_change(awareness)
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      iex> receive do {:awareness_change, %{removed: [], added: [2230489810], updated: []}, _origin, _awareness} -> :ok end
  """
  def monitor_change(%__MODULE__{} = awareness) do
    ref = Yex.Nif.awareness_monitor_change(awareness, self())

    # Subscription should not be automatically released by gc, so put it in the process dictionary
    Process.put(__MODULE__.Subscriptions, [ref | Process.get(__MODULE__.Subscriptions, [])])

    ref
  end

  def demonitor_change(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end

  # protocols

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.encode_update(awareness, [10])
      {:ok, <<1, 10, 1, 15, 123, 34, 107, 101, 121, 34, 58, 34, 118, 97, 108, 117, 101, 34, 125>>}
  """
  def encode_update(awareness, clients) do
    Yex.Nif.awareness_encode_update_v1(awareness, clients)
  end

  @doc """
    /// Applies an update (incoming from remote channel or generated using [Awareness.encode_update] method) and modifies a state of a current instance.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      iex> Yex.Awareness.clean_local_state(awareness)
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      :ok
      iex> Yex.Awareness.get_client_ids(awareness)
      [2230489810]
  """
  def apply_update(awareness, update) do
    Yex.Nif.awareness_apply_update_v1(awareness, update, nil) |> Yex.Nif.Util.unwrap_ok_tuple()
  end

  @doc """
  Clears out a state of a given client, effectively marking it as disconnected.

  ## Examples
      iex> {:ok, _awareness} = Yex.Awareness.new(Yex.Doc.new())
  """
  def remove_states(awareness, clients) do
    Yex.Nif.awareness_remove_states(awareness, clients)
  end
end
