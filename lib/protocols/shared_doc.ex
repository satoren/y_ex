defmodule Yex.Sync.SharedDoc do
  @moduledoc """
  This process handles messages for yjs protocol sync and awareness.
  https://github.com/yjs/y-protocols

  Persistence is supported by passing persistence module.
  see Yex.Sync.SharedDoc.PersistenceBehaviour

  If the observer process does not exist, it will automatically terminate.
  """
  use GenServer

  require Logger
  alias Yex.{Sync, Doc, Awareness}

  @type launch_param ::
          {:doc_name, String.t()}
          | {:persistence, {module() | {module(), init_arg :: term()}}}
          | {:auto_exit, boolean()}

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

  def observe(server) do
    GenServer.call(server, {:observe, self()})
  end

  def unobserve(server) do
    GenServer.call(server, {:unobserve, self()})
  end

  @impl true
  def init(option) do
    doc_name = Keyword.fetch!(option, :doc_name)
    auto_exit = Keyword.get(option, :auto_exit, true)

    {persistence, persistence_init_arg} =
      case Keyword.get(option, :persistence) do
        {module, init_arg} -> {module, init_arg}
        module -> {module, nil}
      end

    doc = Doc.new()
    {:ok, awareness} = Awareness.new(doc)

    Awareness.clean_local_state(awareness)

    persistence_state =
      if function_exported?(persistence, :bind, 3) do
        persistence.bind(persistence_init_arg, doc_name, doc)
      else
        persistence_init_arg
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
       auto_exit: auto_exit,
       observer_process: %{}
     }}
  end

  @impl true
  def handle_call({:observe, client}, _from, state) do
    observer_process =
      Map.put_new_lazy(state.observer_process, client, fn -> Process.monitor(client) end)

    {:reply, :ok, put_in(state.observer_process, observer_process)}
  end

  @impl true
  def handle_call({:unobserve, client}, _from, state) do
    state = do_remove_observer_process(client, state)

    {:reply, :ok, state, 0}
  end

  defp do_remove_observer_process(client, state) do
    {ref, observer_process} = Map.pop(state.observer_process, client)

    if ref != nil do
      Process.demonitor(ref)
    end

    put_in(state.observer_process, observer_process)
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

    {:noreply, state}
  end

  @impl true
  def handle_info({:yjs, message, from}, state) when is_binary(message) do
    case Sync.message_decode(message) do
      {:ok, message} ->
        handle_yjs_message(message, from, state)

      error ->
        Logger.warning(error)
        {:noreply, state}
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
      broadcast_to_users(message, origin, state)
    else
      error ->
        error
    end

    {:noreply, state}
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
      broadcast_to_users(message, origin, state)
    else
      error ->
        Logger.warning(error)
        error
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = do_remove_observer_process(pid, state)

    if state.auto_exit and state.observer_process === %{} do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:timeout, state) do
    if state.auto_exit and state.observer_process === %{} do
      {:stop, :normal, state}
    else
      {:noreply, state}
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

    {:noreply, state}
  end

  defp handle_yjs_message({:awareness, message}, _from, state) do
    Awareness.apply_update(state.awareness, message)
    {:noreply, state}
  end

  defp handle_yjs_message(_, _from, state) do
    # unsupported_message
    {:noreply, state}
  end

  defp broadcast_to_users(message, _origin, state) do
    state.observer_process
    |> Enum.each(fn {pid, _} ->
      send(pid, {:yjs, message, self()})
    end)
  end

  defmodule PersistenceBehaviour do
    @moduledoc """
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
end
