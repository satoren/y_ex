defmodule Yex.DocServer.Worker do
  @moduledoc false
  use GenServer, restart: :temporary
  require Logger

  alias Yex.DocServer.State

  alias Yex.{Doc, Awareness}

  # MSG_QUERY_AWARENESS (<<3>>) — bypass message_decode NIF
  @query_awareness_call :__yex_query_awareness
  @sync_step1_raw_call :__yex_sync_step1_raw
  @sync_update_raw_cast :__yex_sync_update_raw

  @query_awareness_message <<3>>
  def process_message_v1(server, @query_awareness_message, _origin) do
    GenServer.call(server, @query_awareness_call)
  end

  # MSG_SYNC (0) + MSG_SYNC_STEP_1 (0) — bypass message_decode NIF, pass sv_payload directly
  def process_message_v1(server, <<0, 0, sv_payload::binary>>, _origin) do
    GenServer.call(server, {@sync_step1_raw_call, sv_payload})
  end

  # MSG_SYNC (0) + MSG_SYNC_UPDATE (2) — bypass decode NIF and pass raw payload directly
  def process_message_v1(server, <<0, 2, update_payload::binary>>, origin) do
    GenServer.cast(server, {@sync_update_raw_cast, update_payload, origin})
  end

  def process_message_v1(server, message, origin) do
    case Yex.Nif.sync_message_decode_v1(message) do
      {:ok, message} ->
        message_v1(server, message, origin)

      error ->
        error
    end
  end

  #  defp message_v1(server, {:sync, {:sync_step1, encoded_state_vector}}, origin) do
  #    GenServer.call(server, {__MODULE__, :document_sync_step1, encoded_state_vector, origin})
  #  end

  defp message_v1(server, {:sync, {:sync_step2, encoded_diff}}, origin) do
    GenServer.cast(server, {__MODULE__, :document_update, encoded_diff, origin})
  end

  #  defp message_v1(server, {:sync, {:sync_update, encoded_diff}}, origin) do
  #    GenServer.cast(server, {__MODULE__, :document_update, encoded_diff, origin})
  #  end

  defp message_v1(server, {:awareness, awareness}, origin) do
    GenServer.cast(server, {__MODULE__, :awareness_update, awareness, origin})
  end

  #  defp message_v1(server, :query_awareness, _origin) do
  #    GenServer.call(server, @query_awareness_call)
  #  end

  defp message_v1(_server, _message, _origin) do
    {:error, :unknown_message}
  end

  ## Callbacks

  @impl true
  def init(arg) do
    module = Keyword.fetch!(arg, :module)
    option = Keyword.get(arg, :doc_option, nil)
    assigns = Keyword.get(arg, :assigns, %{})
    doc = if option, do: Doc.with_options(option), else: Doc.new()

    if function_exported?(module, :handle_update_v1, 4) do
      Doc.monitor_update_v1(doc, metadata: __MODULE__)
    end

    awareness = setup_awareness(doc, module)

    module.init(arg, %State{
      assigns: assigns,
      doc: doc,
      awareness: awareness,
      module: module
    })
  end

  defp setup_awareness(doc, module) do
    if function_exported?(module, :handle_awareness_change, 4) or
         function_exported?(module, :handle_awareness_update, 4) do
      case Awareness.new(doc) do
        {:ok, awareness} ->
          monitor_awareness_events(awareness, module)

          awareness
      end
    end
  end

  defp monitor_awareness_events(awareness, module) do
    if function_exported?(module, :handle_awareness_change, 4) do
      Awareness.monitor_change(awareness, metadata: __MODULE__)
    end

    if function_exported?(module, :handle_awareness_update, 4) do
      Awareness.monitor_update(awareness, metadata: __MODULE__)
    end
  end

  @impl true
  def handle_call(
        {@sync_step1_raw_call, sv_payload},
        _from,
        %{doc: doc, awareness: awareness} = state
      ) do
    {:reply, Yex.Nif.encode_sync_step1_response_v1(doc, nil, sv_payload, awareness), state}
  end

  @impl true
  def handle_call(
        @query_awareness_call,
        _from,
        %{awareness: nil} = state
      ) do
    {:reply, {:ok, []}, state}
  end

  @impl true
  def handle_call(
        @query_awareness_call,
        _from,
        %{awareness: awareness} = state
      ) do
    {:reply, Yex.Nif.encode_awareness_reply_v1(awareness), state}
  end

  @impl true
  def handle_call(
        {Yex.Doc, :run, fun},
        _from,
        state
      ) do
    {:reply, fun.(), state}
  end

  @impl true
  def handle_call(request, from, %{module: module} = state) do
    module.handle_call(request, from, state)
  end

  @impl true
  def handle_cast(
        {@sync_update_raw_cast, update_payload, origin},
        %{doc: doc} = state
      ) do
    Yex.Doc.transaction(doc, origin, fn ->
      case Yex.Nif.apply_sync_update_payload_v1(doc, cur_txn(doc), update_payload) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.log(:warning, inspect(reason))
          :ok
      end
    end)

    handle_update_v1_immediately(state)
  end

  @impl true
  def handle_cast(
        {__MODULE__, :document_update, update, origin},
        %{doc: doc} = state
      ) do
    Yex.Doc.transaction(doc, origin, fn ->
      case Yex.apply_update(doc, update) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.log(:warning, inspect(reason))
          :ok
      end
    end)

    # Process update messages immediately
    handle_update_v1_immediately(state)
  end

  @impl true
  def handle_cast(
        {__MODULE__, :awareness_update, _message, _origin},
        %{awareness: nil} = state
      ) do
    #    Logger.warning("Received an awareness message, but ignored it because it is not enabled in this module. ")
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {__MODULE__, :awareness_update, message, origin},
        %{awareness: awareness} = state
      ) do
    Awareness.apply_update(awareness, message, origin)

    # Process update messages immediately
    handle_awareness_event_immediately(state)
  end

  @impl true
  def handle_cast(request, %{module: module} = state) do
    module.handle_cast(request, state)
  end

  @impl true
  def handle_info({:update_v1, update, origin, __MODULE__}, %{module: module, doc: doc} = state) do
    module.handle_update_v1(doc, update, origin, state)
  end

  @impl true
  def handle_info(
        {:awareness_change, change, origin, __MODULE__},
        %{module: module, awareness: awareness} = state
      ) do
    module.handle_awareness_change(awareness, change, origin, state)
  end

  @impl true
  def handle_info(
        {:awareness_update, change, origin, __MODULE__},
        %{module: module, awareness: awareness} = state
      ) do
    module.handle_awareness_update(awareness, change, origin, state)
  end

  @impl true
  def handle_info(msg, %{module: module} = state) do
    module.handle_info(msg, state)
  end

  @impl true
  def terminate(reason, %{module: module} = state) do
    if function_exported?(module, :terminate, 2) do
      module.terminate(reason, state)
    else
      :ok
    end
  end

  defp handle_update_v1_immediately(%{doc: doc, module: module} = state) do
    receive do
      {:update_v1, update, origin, __MODULE__} ->
        case module.handle_update_v1(doc, update, origin, state) do
          {:noreply, state} ->
            handle_update_v1_immediately(state)

          result ->
            result
        end
    after
      0 ->
        {:noreply, state}
    end
  end

  defp handle_awareness_event_immediately(%{awareness: awareness, module: module} = state) do
    receive do
      {:awareness_change, change, origin, __MODULE__} ->
        case module.handle_awareness_change(awareness, change, origin, state) do
          {:noreply, state} ->
            handle_awareness_event_immediately(state)

          result ->
            result
        end

      {:awareness_update, change, origin, __MODULE__} ->
        case module.handle_awareness_update(awareness, change, origin, state) do
          {:noreply, state} ->
            handle_awareness_event_immediately(state)

          result ->
            result
        end
    after
      0 ->
        {:noreply, state}
    end
  end

  defp cur_txn(%Yex.Doc{reference: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
