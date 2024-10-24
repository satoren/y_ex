defmodule Yex.DocServer.Handler do
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
    GenServer.call(server, {:document_sync_step1, encoded_state_vector, origin})
    |> handle_process_message_result()
  end

  defp message_v1(server, {:sync, {:sync_step2, encoded_diff}}, origin) do
    GenServer.cast(server, {:document_update, encoded_diff, origin})
  end

  defp message_v1(server, {:sync, {:sync_update, encoded_diff}}, origin) do
    GenServer.cast(server, {:document_update, encoded_diff, origin})
  end

  defp message_v1(server, {:awareness, awareness}, origin) do
    GenServer.cast(server, {:awareness_update, awareness, origin})
  end

  defp message_v1(_server, _message, _origin) do
    {:error, :unknown_message}
  end

  defp handle_process_message_result(result) do
    case result do
      {:ok, replies} ->
        {:ok, Enum.map(replies, fn reply -> Yex.Sync.message_encode!(reply) end)}

      error ->
        error
    end
  end

  ## Callbacks

  @impl true
  def init(arg) do
    module = Keyword.fetch!(arg, :module)
    option = Keyword.get(arg, :doc_option, nil)
    assigns = Keyword.get(arg, :assigns, %{})
    doc = if option, do: Doc.with_options(option), else: Doc.new()

    if function_exported?(module, :handle_update_v1, 4) do
      Doc.monitor_update_v1(doc)
    end

    awareness =
      if function_exported?(module, :handle_awareness_change, 4) do
        {:ok, awareness} = Awareness.new(doc)
        Awareness.monitor_change(awareness)
        awareness
      end

    state = %State{
      assigns: assigns,
      doc: doc,
      awareness: awareness,
      module: module
    }

    module.init(arg, state)
  end

  @impl true
  def handle_call(
        {:document_sync_step1, encoded_state_vector, _origin},
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
          Logger.warning(inspect(error))
          error
      end

    {:reply, replies, state}
  end

  @impl true
  def handle_call(request, from, %{module: module} = state) do
    module.handle_call(request, from, state)
  end

  @impl true
  def handle_cast(
        {:document_update, update, origin},
        %{doc: doc} = state
      ) do
    Yex.Doc.transaction(doc, origin, fn ->
      case Yex.apply_update(doc, update) do
        :ok ->
          :ok

        error ->
          Logger.warning(inspect(error))
          error
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:awareness_update, message, origin},
        %{awareness: nil} = state
      ) do
    Logger.warning("Awareness not initialized")
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:awareness_update, message, origin},
        %{awareness: awareness} = state
      ) do
    Awareness.apply_update(awareness, message, origin)
    {:noreply, state}
  end

  @impl true
  def handle_cast(request, %{module: module} = state) do
    module.handle_cast(request, state)
  end

  @impl true
  def handle_info({:update_v1, update, origin, doc}, %{module: module} = state) do
    module.handle_update_v1(doc, update, origin, state)
  end

  @impl true
  def handle_info(
        {:awareness_change, change, origin, awareness},
        %{module: module} = state
      ) do
    module.handle_awareness_change(awareness, change, origin, state)
  end

  @impl true
  def handle_info(msg, %{module: module} = state) do
    if function_exported?(module, :handle_info, 2) do
      module.handle_info(msg, state)
    else
      {:noreply, state}
    end
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
    awareness_clients = Awareness.get_client_ids(awareness)

    with true <- length(awareness_clients) > 0,
         {:ok, awareness_update} <-
           Awareness.encode_update(awareness, awareness_clients) do
      [awareness_update]
    else
      false ->
        []

      error ->
        Logger.warning(inspect(error))
        []
    end
  end
end
