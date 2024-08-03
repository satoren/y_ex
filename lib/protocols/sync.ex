defmodule Yex.Sync do
  @moduledoc """
  Sync protocol.
  """

  @type sync_message ::
          {:sync_step1, encoded_state_vector :: binary}
          | {:sync_step2, encoded_diff :: binary}
          | {:sync_update, encoded_diff :: binary}
  @type message ::
          {:sync, sync_message} | :query_awareness | {:awareness, message} | {:auth, term}

  @spec message_decode(binary) :: {:ok, message} | {:error, term}
  def message_decode(message), do: message_decode_v1(message)

  @doc """
  Decode a message.

  ## Examples
      iex> Yex.Sync.message_decode(<<0, 0, 1,0>>)
      {:ok, {:sync, {:sync_step1, <<0>>}}}
  """
  @spec message_decode!(binary) :: message
  def message_decode!(message) do
    case message_decode(message) do
      {:ok, message} -> message
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Encode a message.

  ## Examples
      iex> Yex.Sync.message_encode({:sync, {:sync_step1, <<0>>}})
      {:ok, <<0, 0, 1,0>>}
  """
  @spec message_encode(message) :: {:ok, binary} | {:error, term}
  def message_encode(message), do: message_encode_v1(message)

  @spec message_encode!(message) :: binary
  def message_encode!(message) do
    case message_encode(message) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise reason
    end
  end

  @spec message_decode_v1(binary) :: {:ok, message} | {:error, term}
  def message_decode_v1(message), do: Yex.Nif.sync_message_decode_v1(message)
  @spec message_encode_v1(message) :: {:ok, binary} | {:error, term}
  def message_encode_v1(message), do: Yex.Nif.sync_message_encode_v1(message)
  @spec message_decode_v2(binary) :: {:ok, message} | {:error, term}
  def message_decode_v2(message), do: Yex.Nif.sync_message_decode_v2(message)
  @spec message_encode_v2(message) :: {:ok, binary} | {:error, term}
  def message_encode_v2(message), do: Yex.Nif.sync_message_encode_v2(message)

  @doc """
  Create a sync step 1 message based on the state of the current shared document.
  """
  def get_sync_step1(doc) do
    case Yex.encode_state_vector(doc) do
      {:ok, vec} -> {:ok, {:sync_step1, vec}}
      error -> error
    end
  end

  def get_sync_step2(doc, encoded_state_vector) do
    case Yex.encode_state_as_update(doc, encoded_state_vector) do
      {:ok, vec} -> {:ok, {:sync_step2, vec}}
      error -> error
    end
  end

  def get_update(update) do
    {:ok, {:sync_update, update}}
  end

  def read_sync_step1(encoded_state_vector, doc) do
    get_sync_step2(doc, encoded_state_vector)
  end

  def read_sync_step2(update, doc, transactionOrigin) do
    Yex.Doc.transaction(doc, transactionOrigin, fn ->
      case Yex.apply_update(doc, update) do
        :ok -> :ok
        error -> error
      end
    end)
  end

  @spec read_sync_message(sync_message, Yex.Doc.t(), term) :: {:ok, term} | {:error, term}
  def read_sync_message(message, doc, transactionOrigin) do
    case message do
      {:sync_step1, encoded_state_vector} ->
        read_sync_step1(encoded_state_vector, doc)

      {:sync_step2, step2} ->
        read_sync_step2(step2, doc, transactionOrigin)

      {:sync_update, update} ->
        read_sync_step2(update, doc, transactionOrigin)

      _ ->
        {:error, "Unknown message type: "}
    end
  end
end
