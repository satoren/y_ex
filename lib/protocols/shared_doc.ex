defmodule Yex.Sync.SharedDoc do
  @moduledoc """
  This process handles messages for yjs protocol sync and awareness.
  https://github.com/yjs/y-protocols

  Persistence is supported by passing persistence module.
  see Yex.Sync.SharedDoc.PersistenceBehaviour

  If the observer process does not exist, it will automatically terminate.
  """
  use Yex.DocServer

  require Logger
  alias Yex.{Sync, Doc, Awareness}

  @typedoc """
  Launch Parameters

    * `:doc_name` - The name of the document.
    * `:persistence` - Persistence module that implements PersistenceBehaviour.
    * `:auto_exit` - Automatically terminate the SharedDoc process when there is no longer a process to receive update notifications.
    * `:doc_option` - Options for the document.

  """
  @type launch_param ::
          {:doc_name, String.t()}
          | {:persistence, {module() | {module(), init_arg :: term()}}}
          | {:auto_exit, boolean()}
          | {:doc_option, Yex.Doc.Options.t()}

  @doc """
  Send a message to the SharedDoc process.
  message mus be represented in the Yjs protocol default format.
  type supports sync and awareness.
  """
  @deprecated "Use `process_message_v1/3` instead"
  def send_yjs_message(server, message) when is_binary(message) do
    process_message_v1(server, message, self())
    |> handle_process_message_result(server)
  end

  @doc """
  Start the initial state exchange.

  """
  @deprecated "Use `process_message_v1/3` instead"
  def start_sync(server, step1_message) do
    process_message_v1(server, step1_message, self())
    |> handle_process_message_result(server)
  end

  defp handle_process_message_result(result, server) do
    case result do
      {:ok, replies} ->
        Enum.each(replies, fn reply ->
          send(self(), {:yjs, reply, server})
        end)

        :ok

      error ->
        error
    end
  end

  @doc """
  Receive doc update notifications in the calling process.
  """
  def observe(server) do
    GenServer.call(server, {:observe, self()})
  end

  @doc """
  Stop receiving doc update notifications in the calling process.

  If auto_exit is started with true(default), the SharedDoc process will automatically stop when there is no longer a process to receive update notifications.
  """
  def unobserve(server) do
    GenServer.call(server, {:unobserve, self()})
  end

  @impl true
  def init(option, %{doc: doc, awareness: awareness} = state) do
    doc_name = Keyword.fetch!(option, :doc_name)
    auto_exit = Keyword.get(option, :auto_exit, true)

    {persistence, persistence_init_arg} =
      case Keyword.get(option, :persistence) do
        {module, init_arg} -> {module, init_arg}
        module -> {module, nil}
      end

    Code.ensure_loaded(persistence)

    Awareness.clean_local_state(awareness)

    persistence_state =
      if function_exported?(persistence, :bind, 3) do
        persistence.bind(persistence_init_arg, doc_name, doc)
      else
        persistence_init_arg
      end

    {:ok,
     assign(
       state,
       %{
         doc_name: doc_name,
         persistence: persistence,
         persistence_state: persistence_state,
         auto_exit: auto_exit,
         observer_process: %{}
       }
     )}
  end

  @impl true
  def handle_call({:observe, client}, _from, state) do
    observer_process =
      Map.put_new_lazy(state.assigns.observer_process, client, fn -> Process.monitor(client) end)

    {:reply, :ok, assign(state, :observer_process, observer_process)}
  end

  @impl true
  def handle_call({:unobserve, client}, _from, state) do
    state = do_remove_observer_process(client, state)

    {:reply, :ok, state, 0}
  end

  defp do_remove_observer_process(client, state) do
    {ref, observer_process} = Map.pop(state.assigns.observer_process, client)

    if ref != nil do
      Process.demonitor(ref)
    end

    assign(state, :observer_process, observer_process)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = do_remove_observer_process(pid, state)

    if state.assigns.auto_exit and state.assigns.observer_process === %{} do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:timeout, state) do
    if state.assigns.auto_exit and state.assigns.observer_process === %{} do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_awareness_change(
        awareness,
        %{removed: removed, added: added, updated: updated},
        origin,
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

  @impl true
  def handle_update_v1(_doc, update, origin, %{assigns: assigns} = state) do
    state =
      if function_exported?(assigns.persistence, :update_v1, 4) do
        persistence_state =
          assigns.persistence.update_v1(
            state.assigns.persistence_state,
            update,
            state.assigns.doc_name,
            state.doc
          )

        assign(state, :persistence_state, persistence_state)
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
  def terminate(_reason, %{assigns: assigns} = state) do
    if function_exported?(assigns.persistence, :unbind, 3) do
      state.assigns.persistence.unbind(assigns.persistence_state, assigns.doc_name, state.doc)
    end

    :ok
  end

  defp broadcast_to_users(message, origin, state) do
    state.assigns.observer_process
    |> Enum.filter(fn {pid, _} -> pid != origin end)
    |> Enum.each(fn {pid, _} ->
      send(pid, {:yjs, message, self()})
    end)
  end

  defmodule PersistenceBehaviour do
    @moduledoc """
    Persistence behavior for SharedDoc
    """

    @doc """
    Invoked to handle SharedDoc bind.
    Mainly used to read and set the initial values of SharedDoc


    ## Examples save the state to the filesystem
      def bind(state, doc_name, doc) do
        case File.read("path/to/" <> doc_name, [:read, :binary]) do
          {:ok, data} ->
            Yex.apply_update(doc, data)

          {:error, _} ->
            :ok
        end
      end
    """
    @callback bind(state :: term(), doc_name :: String.t(), doc :: Doc.t()) :: term()

    @doc """
    Invoked to handle SharedDoc terminate.

    This is only executed when SharedDoc exits successfully.

    ## Examples save the state to the filesystem
        def unbind(state, doc_name, doc) do
          case Yex.encode_state_as_update(doc) do
            {:ok, update} ->
              File.write!("path/to/" <> doc_name, update, [:write, :binary])
            error ->
              error
          end

          :ok
        end
    """
    @callback unbind(state :: term(), doc_name :: String.t(), doc :: Doc.t()) :: :ok

    @doc """
    Invoked to handle all doc updates.
    """
    @callback update_v1(
                state :: term(),
                update :: binary(),
                doc_name :: String.t(),
                doc :: Doc.t()
              ) :: term()

    @optional_callbacks update_v1: 4, unbind: 3
  end
end
