defmodule Yex.Managed.SharedDoc do
  @moduledoc false
  @doc """
  This module is experimental

  Automatically synchronized document processes within the same process group.
  This is synchronized cluster-wide.

  Note: this uses :pg.monitor and requires OTP 25.1 or higher.

  vs Yex.Sync.SharedDoc
  Because a copy is maintained for each cluster, the amount of communication between clusters may be reduced, but memory usage will increase.

  """
  use GenServer

  require Logger
  alias Yex.{Sync, Doc, Awareness}

  @default_idle_timeout 15_000

  @type launch_param ::
          {:doc_name, String.t()}
          | {:persistence, {module() | {module(), init_arg :: term()}}}
          | {:idle_timeout, integer()}
          | {:pg_scope, atom()}
          | {:local_pubsub, module()}

  @spec start_link(param :: [launch_param], option :: GenServer.options()) :: GenServer.on_start()
  def start_link(param, option \\ []) do
    GenServer.start_link(__MODULE__, param, option)
  end

  @spec start(param :: [launch_param], option :: GenServer.options()) :: GenServer.on_start()
  def start(param, option \\ []) do
    GenServer.start(__MODULE__, param, option)
  end

  def send_yjs_message(server, message) when is_binary(message) do
    send(GenServer.whereis(server), {:yjs, message, self()})
  end

  def start_sync(server, step1_message) do
    send(GenServer.whereis(server), {:start_sync, step1_message, self()})
  end

  def doc_name(server) do
    GenServer.call(server, :doc_name)
  end

  @impl true
  def init(option) do
    doc_name = Keyword.fetch!(option, :doc_name)

    {persistence, persistence_init_arg} =
      case Keyword.get(option, :persistence) do
        {module, init_arg} -> {module, init_arg}
        module -> {module, nil}
      end

    timeout = Keyword.get(option, :idle_timeout, @default_idle_timeout)
    pg_scope = Keyword.get(option, :pg_scope, nil)
    local_pubsub = Keyword.get(option, :local_pubsub, nil)
    doc = Doc.new()
    {:ok, awareness} = Awareness.new(doc)

    Awareness.clean_local_state(awareness)

    persistence_state =
      if function_exported?(persistence, :bind, 3) do
        persistence.bind(persistence_init_arg, doc_name, doc)
      else
        persistence_init_arg
      end

    {:ok, step1_data} = Sync.get_sync_step1(doc)
    message = Sync.message_encode!({:sync, step1_data})
    step1 = {:yjs, message, self()}

    if local_pubsub != nil do
      local_pubsub.broadcast(
        doc_name,
        step1,
        ""
      )
    end

    if pg_scope != nil do
      :pg.join(pg_scope, doc_name, self())
      {_group_monitor_ref, pids} = :pg.monitor(pg_scope, doc_name)

      pids
      |> Enum.reject(&(&1 == self()))
      |> Enum.each(fn pid ->
        send(pid, step1)
      end)
    end

    Doc.monitor_update_v1(doc)
    Awareness.monitor_change(awareness)

    {:ok,
     %{
       doc: doc,
       awareness: awareness,
       doc_name: doc_name,
       persistence: persistence,
       persistence_state: persistence_state,
       timeout: timeout,
       pg_scope: pg_scope,
       local_pubsub: local_pubsub
     }, timeout}
  end

  @impl true
  def handle_call(:doc_name, _from, state) do
    {:reply, state.doc_name, state, state.timeout}
  end

  @impl true
  def handle_info({:start_sync, message, from}, state) when is_binary(message) do
    with {:ok, {:sync, sync_message}} <- Sync.message_decode(message),
         {:ok, reply} <- Sync.read_sync_message(sync_message, state.doc, "#{inspect(from)}"),
         {:ok, sync_message} <- Sync.message_encode({:sync, reply}) do
      send(from, {:yjs, sync_message, self()})

      with {:ok, step1} <- Sync.get_sync_step1(state.doc),
           {:ok, step1} <- Sync.message_encode({:sync, step1}) do
        send(from, {:yjs, step1, self()})
      else
        error ->
          error
      end

      awareness_clients = Awareness.get_client_ids(state.awareness)

      with true <- length(awareness_clients) > 0,
           {:ok, awareness_update} <-
             Awareness.encode_update(state.awareness, awareness_clients) do
        send(from, {:yjs, Sync.message_encode!({:awareness, awareness_update}), self()})
      else
        false -> :ok
        error -> error
      end
    else
      error ->
        error
    end

    {:noreply, state, state.timeout}
  end

  @impl true
  def handle_info({:yjs, message, from}, state) when is_binary(message) do
    case Sync.message_decode(message) do
      {:ok, message} ->
        handle_yjs_message(message, from, state)

      error ->
        Logger.error(error)
        {:noreply, state, state.timeout}
    end
  end

  @impl true
  def handle_info({:update_v1, update, origin, _doc}, state) do
    state =
      if function_exported?(state.persistence, :update_v1, 4) do
        persistence_state =
          state.persistence.update_v1(state.persistence_state, update, state.doc_name, state.doc)

        put_in(state.persistence_state, persistence_state)
      else
        state
      end

    with {:ok, s} <- Sync.get_update(update),
         {:ok, message} <- Sync.message_encode({:sync, s}) do
      broadcast_to_group_process(message, origin, state)

      broadcast_to_users(message, origin, state)
    else
      error ->
        error
    end

    {:noreply, state, state.timeout}
  end

  @impl true
  def handle_info(
        {:awareness_change, %{removed: removed, added: added, updated: updated}, origin,
         awareness},
        state
      ) do
    changed_clients = added ++ updated ++ removed

    with {:ok, update} <- Awareness.encode_update(awareness, changed_clients),
         {:ok, message} <- Sync.message_encode({:awareness, update}) do
      broadcast_to_group_process(message, origin, state)
      broadcast_to_users(message, origin, state)
    else
      error ->
        Logger.error(error)
        error
    end

    {:noreply, state, state.timeout}
  end

  def handle_info({_ref, :join, _group, pids}, %{doc: doc} = state) do
    with {:ok, s} <- Sync.get_sync_step1(doc),
         {:ok, step1} <- Sync.message_encode({:sync, s}) do
      pids
      |> Enum.each(fn pid ->
        send(pid, {:yjs, step1, self()})
      end)
    else
      error ->
        Logger.error(error)
        error
    end

    {:noreply, state, state.timeout}
  end

  def handle_info({_ref, :leave, _group, _pids}, state) do
    {:noreply, state, state.timeout}
  end

  def handle_info(:timeout, state) do
    if should_exit?(state) do
      {:stop, :normal, state}
    else
      {:noreply, state, state.timeout}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if function_exported?(state.persistence, :unbind, 3) do
      state.persistence.unbind(state.persistence_state, state.doc_name, state.doc)
    end

    :ok
  end

  defp handle_yjs_message({:sync, sync_message}, from, state) do
    with {:ok, reply} <- Sync.read_sync_message(sync_message, state.doc, "#{inspect(from)}"),
         {:ok, sync_message} <- Sync.message_encode({:sync, reply}) do
      send(from, {:yjs, sync_message, self()})
    else
      error ->
        error
    end

    {:noreply, state, state.timeout}
  end

  defp handle_yjs_message({:awareness, message}, _from, state) do
    Awareness.apply_update(state.awareness, message)
    {:noreply, state, state.timeout}
  end

  defp handle_yjs_message(_, _from, state) do
    # unsupported_message
    {:noreply, state, state.timeout}
  end

  defp should_exit?(state) do
    state.local_pubsub && state.local_pubsub.monitor_count(state.doc_name) === 0
  end

  defp broadcast_to_users(message, origin, state) do
    if state.local_pubsub != nil do
      state.local_pubsub.broadcast(
        state.doc_name,
        {:yjs, message, self()},
        origin
      )
    end
  end

  defp broadcast_to_group_process(message, _origin, state) do
    if state.pg_scope != nil do
      :pg.get_members(state.pg_scope, state.doc_name)
      |> Enum.reject(&(&1 == self()))
      |> Enum.each(fn pid ->
        send(pid, {:yjs, message, self()})
      end)
    end
  end

  defmodule PersistenceBehaviour do
    @moduledoc false
    @doc """
    Persistence behavior for SharedDoc
    """

    @callback bind(state :: term(), doc_name :: String.t(), doc :: Doc.t()) :: term()
    @callback unbind(state :: term(), doc_name :: String.t(), doc :: Doc.t()) :: :ok
    @callback update_v1(
                state :: term(),
                update :: binary(),
                doc_name :: String.t(),
                doc :: Doc.t()
              ) :: term()

    @optional_callbacks update_v1: 4, unbind: 3
  end

  defmodule LocalPubSubBehaviour do
    @moduledoc false
    @doc """
    LocalPubSub behavior for SharedDoc
    Used to notify SharedDoc users of updates.

    see Yex.Managed.SharedDocSupervisor.LocalPubsub for an example implementation
    """

    @callback monitor_count(doc_name :: String.t()) :: integer()
    @callback broadcast(doc_name :: String.t(), message :: term(), exclude_origin :: term()) ::
                :ok

    @callback monitor(doc_name :: String.t()) :: :ok
    @callback demonitor(doc_name :: String.t()) :: :ok
  end
end
