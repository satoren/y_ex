defmodule Yex do
  @moduledoc """
  Yex is wrapper library for the Yjs CRDT library.
  """

  @type input_type ::
          :binary
          | :string
          | :map
          | :list
          | :integer
          | :float
          | :boolean
          | nil
          | Yex.MapPrelim.t()
          | Yex.TextPrelim.t()
          | Yex.ArrayPrelim.t()

  @doc """
  Computes the state vector and encodes it into an Binary.
  A state vector describes the state of the local client.
  The remote client can use this to exchange only the missing differences.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_vector(doc)
  """
  @spec encode_state_vector(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector(%Yex.Doc{} = doc) do
    encode_state_vector_v1(doc)
  end

  @doc """
  @see encode_state_vector/1
  """
  @spec encode_state_vector!(Yex.Doc.t()) :: binary()
  def encode_state_vector!(%Yex.Doc{} = doc) do
    case encode_state_vector(doc) do
      {:ok, binary} -> binary
      {:error, reason} -> raise reason
    end
  end

  def encode_state_vector_v1(%Yex.Doc{} = doc) do
    Yex.Nif.encode_state_vector_v1(doc, cur_txn(doc))
  end

  def encode_state_vector_v2(%Yex.Doc{} = doc) do
    Yex.Nif.encode_state_vector_v2(doc, cur_txn(doc))
  end

  @doc """
  Encode the document state as a single update message that can be applied on the remote document. Optionally, specify the target state vector to only write the missing differences to the update message.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_as_update(doc)
  """
  @spec encode_state_as_update(Yex.Doc.t(), binary() | nil) :: {:ok, binary()} | {:error, term()}
  def encode_state_as_update(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    encode_state_as_update_v1(doc, encoded_state_vector)
  end

  @doc """
  @see encode_state_as_update/2
  """
  @spec encode_state_as_update!(Yex.Doc.t(), binary() | nil) :: binary()
  def encode_state_as_update!(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    case encode_state_as_update(doc, encoded_state_vector) do
      {:ok, binary} -> binary
      {:error, {:encoding_exception, message}} -> raise ArgumentError, message: message
      {:error, reason} -> raise reason
    end
  end

  def encode_state_as_update_v1(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    Yex.Nif.encode_state_as_update_v1(doc, cur_txn(doc), encoded_state_vector)
  end

  def encode_state_as_update_v2(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    Yex.Nif.encode_state_as_update_v2(doc, cur_txn(doc), encoded_state_vector)
  end

  @doc """
  Apply a document update on the shared document.

  ## Examples syncs two clients by exchanging the complete document structure
      iex> doc1 = Yex.Doc.new()
      iex> doc2 = Yex.Doc.new()
      iex> {:ok, state1} = Yex.encode_state_as_update(doc1)
      iex> {:ok, state2} = Yex.encode_state_as_update(doc2)
      iex> Yex.apply_update(doc1, state2)
      :ok
      iex> Yex.apply_update(doc2, state1)
      :ok
  """
  @spec apply_update(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update(%Yex.Doc{} = doc, update) do
    apply_update_v1(doc, update)
  end

  @spec apply_update_v1(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update_v1(%Yex.Doc{} = doc, update) do
    Yex.Nif.apply_update_v1(doc, cur_txn(doc), update)
  end

  @spec apply_update_v2(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update_v2(%Yex.Doc{} = doc, update) do
    Yex.Nif.apply_update_v2(doc, cur_txn(doc), update)
  end

  defp cur_txn(%Yex.Doc{reference: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
