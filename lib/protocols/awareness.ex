defmodule Yex.Awareness do
  @moduledoc """
  Awareness is an optional feature that works well together with Yjs.

  """

  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: reference()
        }

  @doc """
  create a new awareness instance
  """
  @spec new(Yex.Doc.t()) :: {:ok, Yex.Awareness.t()}
  def new(doc), do: {:ok, Yex.Nif.awareness_new(doc)}

  # crdt api

  @spec client_id(t) :: integer()
  def client_id(%__MODULE__{} = awareness), do: Yex.Nif.awareness_client_id(awareness)

  @doc """
  get local state of the current client
  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.get_states(awareness)
      %{}
  """
  @spec get_local_state(t) :: map
  def get_local_state(%__MODULE__{} = awareness), do: Yex.Nif.awareness_get_local_state(awareness)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.get_states(awareness)
      %{100 => %{"key" => "value"}}
  """
  @spec set_local_state(t, map) :: :ok
  def set_local_state(%__MODULE__{} = awareness, map),
    do: Yex.Nif.awareness_set_local_state(awareness, map)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.clean_local_state(awareness)
      iex> Yex.Awareness.get_client_ids(awareness)
      []
  """
  @spec clean_local_state(t) :: :ok
  def clean_local_state(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_clean_local_state(awareness)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      iex> Yex.Awareness.get_client_ids(awareness)
      [2230489810]
  """
  @spec get_client_ids(t) :: [integer()]
  def get_client_ids(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_get_client_ids(awareness)

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 100 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.get_states(awareness)
      %{100 => %{"key" => "value"}}
  """
  @spec get_states(t) :: %{integer() => term()}
  def get_states(%__MODULE__{} = awareness),
    do: Yex.Nif.awareness_get_states(awareness)

  @doc """
   Monitor to remote and local awareness changes. This event is called even when the awareness state does not change but is only updated to notify other users that this client is still online. Use this event if you want to propagate awareness state to other users.
   You can pass metadata as an option. This value is passed as the fourth element of the message.If omitted, it will be passed as a structure of awareness itself.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.monitor_update(awareness)
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> receive do {:awareness_update, %{removed: [], added: [10], updated: []}, _origin, _awareness} -> :ok end
  """
  @spec monitor_update(t, keyword()) :: reference()
  def monitor_update(%__MODULE__{} = awareness, opt \\ []) do
    sub =
      Yex.Nif.awareness_monitor_update(awareness, self(), Keyword.get(opt, :metadata, awareness))

    Yex.Subscription.register(sub)
  end

  @spec demonitor_update(reference()) :: :ok
  def demonitor_update(ref) do
    Yex.Subscription.unsubscribe(ref)
  end

  @doc """
   Listen to remote and local state changes. Get notified when a state is either added, updated, or removed.
   You can pass metadata as an option. This value is passed as the fourth element of the message.If omitted, it will be passed as a structure of awareness itself.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.monitor_change(awareness, metadata: %{ "key" => "value" })
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      iex> receive do {:awareness_change, %{removed: [], added: [2230489810], updated: []}, _origin,  %{ "key" => "value" } = _metadata} -> :ok end
  """
  @spec monitor_change(t, keyword()) :: reference()
  def monitor_change(%__MODULE__{} = awareness, opt \\ []) do
    sub =
      Yex.Nif.awareness_monitor_change(awareness, self(), Keyword.get(opt, :metadata, awareness))

    Yex.Subscription.register(sub)
  end

  @spec demonitor_change(reference()) :: :ok
  def demonitor_change(ref) do
    Yex.Subscription.unsubscribe(ref)
  end

  # protocols

  @doc """


  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{ client_id: 10 }))
      iex> Yex.Awareness.set_local_state(awareness, %{ "key" => "value" })
      iex> Yex.Awareness.encode_update(awareness, [10])
      {:ok, <<1, 10, 1, 15, 123, 34, 107, 101, 121, 34, 58, 34, 118, 97, 108, 117, 101, 34, 125>>}
  """
  @spec encode_update(t, [integer()] | nil) :: {:ok, binary()} | {:error, term()}
  def encode_update(awareness, clients \\ nil) do
    Yex.Nif.awareness_encode_update_v1(awareness, clients)
  end

  @doc """
    Applies an update (incoming from remote channel or generated using [Awareness.encode_update] method) and modifies a state of a current instance.

  ## Examples
      iex> {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      iex> Yex.Awareness.clean_local_state(awareness)
      iex> Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
      :ok
      iex> Yex.Awareness.get_client_ids(awareness)
      [2230489810]
  """
  @spec apply_update(t, binary(), origin :: term() | nil) :: :ok
  def apply_update(awareness, update, origin \\ nil) do
    Yex.Nif.awareness_apply_update_v1(awareness, update, origin)
  end

  @doc """
  Clears out a state of a given client, effectively marking it as disconnected.

  ## Examples
      iex> {:ok, _awareness} = Yex.Awareness.new(Yex.Doc.new())
  """
  @spec remove_states(t, [integer()]) :: :ok
  def remove_states(awareness, clients) do
    Yex.Nif.awareness_remove_states(awareness, clients)
  end
end
