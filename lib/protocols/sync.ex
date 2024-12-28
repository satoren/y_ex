defmodule Yex.Sync do
  @moduledoc """
  Yex.Sync provides functions to handle the synchronization protocol for Yex documents.

  This module defines a set of message types and encoding/decoding functions to manage
  document state synchronization. The messages follow the protocol described in the
  [Yjs Sync Protocol Documentation](https://github.com/yjs/y-protocols/blob/33d220757004da44dc33172ec6aec3b94363052a/PROTOCOL.md#sync-protocol-v1-encoding).
  Each message type corresponds to a step in the sync process or an update to the document state.
  """

  @type sync_message_step1 ::
          {:sync_step1, encoded_state_vector :: binary}
  @type sync_message_step2 ::
          {:sync_step2, document_state :: binary}
  @type sync_message_update ::
          {:sync_update, encoded_diff :: binary}
  @type sync_message ::
          sync_message_step1
          | sync_message_step2
          | sync_message_update
  @type message ::
          {:sync, sync_message} | :query_awareness | {:awareness, message} | {:auth, term}

  @doc """
  Decodes a binary message into a recognized protocol format, returning `{:ok, message}`
  if decoding is successful, or `{:error, reason}` otherwise.

  ## Examples

      iex> Yex.Sync.message_decode(<<0, 0, 1, 0>>)
      {:ok, {:sync, {:sync_step1, <<0>>}}}
  """
  @spec message_decode(binary) :: {:ok, message} | {:error, term}
  def message_decode(message), do: message_decode_v1(message)

  @doc """
  Decodes a binary message, raising an error if decoding fails. Useful for cases where
  error handling is managed at a higher level.

  ## Examples

      iex> Yex.Sync.message_decode!(<<0, 0, 1, 0>>)
      {:sync, {:sync_step1, <<0>>}}
  """
  @spec message_decode!(binary) :: message
  def message_decode!(message) do
    case message_decode(message) do
      {:ok, message} -> message
      {:error, {:encoding_exception, reason}} -> raise reason
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Encodes a message into binary format, returning `{:ok, binary}` if encoding
  succeeds or `{:error, reason}` on failure.

  ## Examples

      iex> Yex.Sync.message_encode({:sync, {:sync_step1, <<0>>}})
      {:ok, <<0, 0, 1, 0>>}
  """
  @spec message_encode(message) :: {:ok, binary} | {:error, term}
  def message_encode(message), do: message_encode_v1(message)

  @doc """
  Encodes a message into binary format and raises an error if encoding fails.
  This function is useful when error handling is managed externally.
  """
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
  Generates a `sync_step1` message for initiating document synchronization. This message
  contains the current encoded state vector of the document.

  Returns `{:ok, {:sync_step1, encoded_state_vector}}` if successful, otherwise an error.
  """
  @spec get_sync_step1(Yex.Doc.t()) ::
          {:ok, sync_message_step1} | {:error, term}
  def get_sync_step1(doc) do
    case Yex.encode_state_vector(doc) do
      {:ok, vec} -> {:ok, {:sync_step1, vec}}
      error -> error
    end
  end

  @doc """
  Creates a `sync_step2` message to continue synchronization using a given encoded state vector.
  This message contains the current state of the document to be synchronized.

  Returns `{:ok, {:sync_step2, document_state}}` if successful, otherwise an error.
  """
  @spec get_sync_step2(Yex.Doc.t(), binary) ::
          {:ok, sync_message_step2} | {:error, term}
  def get_sync_step2(doc, encoded_state_vector) when is_binary(encoded_state_vector) do
    case Yex.encode_state_as_update(doc, encoded_state_vector) do
      {:ok, vec} -> {:ok, {:sync_step2, vec}}
      error -> error
    end
  end

  @doc """
  Generates a `sync_update` message based on a provided update binary. This is typically
  used to apply incremental changes to the document state.

  Returns `{:ok, {:sync_update, update}}`.
  """
  @spec get_update(binary) :: {:ok, sync_message_update} | {:error, term}
  def get_update(update) when is_binary(update) do
    {:ok, {:sync_update, update}}
  end

  @doc """
  Processes a `sync_step1` message to produce a `sync_step2` response, used to
  synchronize document state.

  Returns `{:ok, {:sync_step2, document_state}}` if successful.
  """
  @spec read_sync_step1(binary, Yex.Doc.t()) ::
          {:ok, sync_message_step2} | {:error, term}
  def read_sync_step1(encoded_state_vector, doc) do
    get_sync_step2(doc, encoded_state_vector)
  end

  @doc """
  Processes a `sync_step2` or `sync_update` message by applying the update to the document.
  The update is applied within a transaction to ensure document consistency.

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec read_sync_step2(binary, Yex.Doc.t(), term) :: :ok | {:error, term}
  def read_sync_step2(update, doc, transactionOrigin) do
    Yex.Doc.transaction(doc, transactionOrigin, fn ->
      case Yex.apply_update(doc, update) do
        :ok -> :ok
        error -> error
      end
    end)
  end

  @doc """
  Reads and applies a synchronization message to the document, based on the message type.
  Supports `sync_step1`, `sync_step2`, and `sync_update` messages, with each type invoking
  the appropriate handler.

  Returns `{:ok, response}` on success or `{:error, :unknown_message}` if the message type is invalid.
  """
  @spec read_sync_message(
          sync_message,
          Yex.Doc.t(),
          term
        ) :: {:ok, sync_message_step2} | :ok | {:error, :unknown_message} | {:error, term}
  def read_sync_message(message, doc, transactionOrigin) do
    case message do
      {:sync_step1, encoded_state_vector} ->
        read_sync_step1(encoded_state_vector, doc)

      {:sync_step2, step2} ->
        read_sync_step2(step2, doc, transactionOrigin)

      {:sync_update, update} ->
        read_sync_step2(update, doc, transactionOrigin)

      _ ->
        {:error, :unknown_message}
    end
  end
end
