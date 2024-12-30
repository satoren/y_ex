defmodule Yex.DocServer.Worker do
  @moduledoc false
  use GenServer, restart: :temporary
  require Logger

  alias Yex.DocServer.State

  alias Yex.{Doc, Awareness}

  def process_message_v1(server, message, origin) do
    case Yex.Sync.message_decode(message) do
      {:ok, message} ->
        message_v1(server, message, origin)

      error ->
        error
    end
  end

  defp message_v1(server, {:sync, {:sync_step1, encoded_state_vector}}, origin) do
    GenServer.call(server, {__MODULE__, :document_sync_step1, encoded_state_vector, origin})
    |> handle_process_message_result()
  end

  defp message_v1(server, {:sync, {message_type, encoded_diff}}, origin)
       when message_type in [:sync_step2, :sync_update] do
    GenServer.cast(server, {__MODULE__, :document_update, encoded_diff, origin})
  end

  defp message_v1(server, {:awareness, awareness}, origin) do
    GenServer.cast(server, {__MODULE__, :awareness_update, awareness, origin})
  end

  defp message_v1(server, :query_awareness, _origin) do
    GenServer.call(server, {__MODULE__, :query_awareness})
    |> handle_process_message_result()
  end

  defp message_v1(_server, _message, _origin) do
    {:error, :unknown_message}
  end

  defp handle_process_message_result({:ok, replies}) do
    replies
    |> Enum.reduce_while({:ok, []}, fn reply, {:ok, acc} ->
      case Yex.Sync.message_encode(reply) do
        {:ok, encoded} ->
          {:cont, {:ok, [encoded | acc]}}

        {:error, reason} ->
          Logger.error("Failed to encode reply: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, encoded_replies} -> {:ok, Enum.reverse(encoded_replies)}
      error -> error
    end
  end

  defp handle_process_message_result(error), do: error

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

    awareness =
      if function_exported?(module, :handle_awareness_change, 4) do
        case Awareness.new(doc) do
          {:ok, awareness} ->
            Awareness.monitor_change(awareness, metadata: __MODULE__)
            awareness
        end
      end

    module.init(arg, %State{
      assigns: assigns,
      doc: doc,
      awareness: awareness,
      module: module
    })
  end

  @impl true
  def handle_call(
        {__MODULE__, :document_sync_step1, encoded_state_vector, _origin},
        _from,
        %{doc: doc, awareness: awareness} = state
      ) do
    replies =
      with {:ok, update} <- Yex.encode_state_as_update(doc, encoded_state_vector),
           {:ok, sv} <- Yex.encode_state_vector(doc) do
        {:ok,
         [{:sync, {:sync_step2, update}}, {:sync, {:sync_step1, sv}}] ++
           get_awareness_update(doc, awareness)}
      else
        error ->
          error
      end

    {:reply, replies, state}
  end

  @impl true
  def handle_call(
        {__MODULE__, :query_awareness},
        _from,
        %{doc: doc, awareness: awareness} = state
      ) do
    replies = {:ok, get_awareness_update(doc, awareness)}
    {:reply, replies, state}
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
        {__MODULE__, :document_update, update, origin},
        %{doc: doc} = state
      ) do
    Yex.Doc.transaction(doc, origin, fn ->
      case Yex.apply_update(doc, update) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(inspect(reason))
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
    handle_awareness_change_immediately(state)
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

  defp get_awareness_update(_doc, nil), do: []

  defp get_awareness_update(_doc, awareness) do
    case Awareness.encode_update(awareness) do
      {:ok, awareness_update} ->
        [{:awareness, awareness_update}]

      {:error, reason} ->
        Logger.warning(inspect(reason))
        []
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

  defp handle_awareness_change_immediately(%{awareness: awareness, module: module} = state) do
    receive do
      {:awareness_change, change, origin, __MODULE__} ->
        case module.handle_awareness_change(awareness, change, origin, state) do
          {:noreply, state} ->
            handle_awareness_change_immediately(state)

          result ->
            result
        end
    after
      0 ->
        {:noreply, state}
    end
  end
end
