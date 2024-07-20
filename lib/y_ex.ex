defmodule Yex do
  @moduledoc """
  Documentation for `Yex`.
  """

  @doc """
  Computes the state vector and encodes it into an Uint8Array. A state vector describes the state of the local client. The remote client can use this to exchange only the missing differences.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> Yex.encode_state_vector(doc)
      {:ok, <<0>>}
  """
  @spec encode_state_vector(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector(%Yex.Doc{} = doc) do
    Yex.Nif.encode_state_vector(doc)
  end

  @spec encode_state_vector!(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector!(%Yex.Doc{} = doc) do
    case encode_state_vector(doc) do
      {:ok, binary} -> binary
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Encode the document state as a single update message that can be applied on the remote document. Optionally, specify the target state vector to only write the missing differences to the update message.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> Yex.encode_state_as_update(doc)
      {:ok, <<0, 0>>}
  """
  @spec encode_state_as_update(Yex.Doc.t(), binary()) :: {:ok, binary()} | {:error, term()}
  def encode_state_as_update(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    Yex.Nif.encode_state_as_update(doc, encoded_state_vector)
  end

  @spec encode_state_as_update!(Yex.Doc.t(), binary()) :: binary()
  def encode_state_as_update!(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    case encode_state_as_update(doc, encoded_state_vector) do
      {:ok, binary} -> binary
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Apply a document update on the shared document.

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc1 = Yex.Doc.new()
      iex> doc2 = Yex.Doc.new()
      iex> {:ok, state1} = Yex.encode_state_as_update(doc1)
      iex> {:ok, state2} = Yex.encode_state_as_update(doc2)
      iex> Yex.apply_update(doc1, state2)
      :ok
      iex> Yex.apply_update(doc2, state1)
      :ok
  """
  @spec apply_update(Yex.Doc.t(), binary()) :: :ok
  def apply_update(%Yex.Doc{} = doc, update) do
    Yex.Nif.apply_update(doc, update) |> unwrap_ok_tuple()
  end

  defp unwrap_ok_tuple({:ok, {}}), do: :ok
  defp unwrap_ok_tuple(other), do: other
end
