defmodule Yex.StickyIndex do
  @moduledoc """
  A sticky index provides position references that are unaffected by document changes, based on the Yjs model.
  It maintains its relative position when placed before or after specific characters or elements.

  ## Features
  - Stable position references unaffected by document changes
  - Compatible with shared types like Text, Array, and XML
  - Maintains relative positions after insert/delete operations
  - Ideal for tracking cursor positions and text selections

  ## Usage
  Numeric indices are unsuitable for tracking user selections because their positions
  change when content is inserted or deleted. Sticky indices provide stable references
  that maintain their relative positions through such changes:

      iex> alias Yex.{StickyIndex, Doc, Text}
      iex> doc = Doc.new()
      iex> txt = Doc.get_text(doc, "text")
      iex> Doc.transaction(doc, fn ->
      ...>  Text.insert(txt, 0, "abc")
      ...>  # => 'abc'
      ...>  # Create position tracker (marked as . in comments)
      ...>  pos = StickyIndex.new(txt, 2, :after)
      ...>  # => 'ab.c'
      ...>
      ...>  # Modify text
      ...>  Text.insert(txt, 1, "def")
      ...>  # => 'adefb.c'
      ...>  Text.delete(txt, 4, 1)
      ...>  # => 'adef.c'
      ...>
      ...>  # Get current offset index
      ...>  {:ok, a} = StickyIndex.get_offset(pos)
      ...>  # => 4
      ...>  assert a.index == 4
      ...> end)
  """
  defstruct [
    :doc,
    :reference,
    :assoc
  ]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference(),
          assoc: :before | :after
        }

  alias Yex.Doc
  require Yex.Doc

  @type shared_type ::
          %Yex.Array{}
          | %Yex.Text{}
          | %Yex.XmlElement{}
          | %Yex.XmlText{}
          | %Yex.XmlFragment{}
  @spec new(shared_type, integer(), :before | :after) :: t
  def new(%{doc: doc} = shared_type, index, assoc) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.sticky_index_new(shared_type, cur_txn(shared_type), index, assoc)
    )
  end

  @spec get_offset(t) :: {:ok, %{index: integer(), assoc: :before | :after}} | :error
  def get_offset(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.sticky_index_get_offset(sticky_index, cur_txn(sticky_index))
    )
  end

  @doc """
  Encodes a StickyIndex to binary format using flexbuffer encoding (v1 - default).

  This provides a compact binary representation suitable for storage or transmission.
  The encoded binary can be decoded using `decode/2` or `decode_v1/2`.
  """
  @spec encode(t) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_encode(sticky_index))
  end

  @doc """
  Encodes a StickyIndex to binary flexbuffer format (v1).
  """
  @spec encode_v1(t) :: {:ok, binary()} | {:error, term()}
  def encode_v1(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_encode_v1(sticky_index))
  end

  @doc """
  Encodes a StickyIndex to JSON string format (v2).

  This provides a JSON string representation of the StickyIndex suitable for
  interoperability with other systems.
  """
  @spec encode_v2(t) :: {:ok, binary()} | {:error, term()}
  def encode_v2(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_encode_v2(sticky_index))
  end

  @doc """
  Decodes a StickyIndex from binary format with the given Doc context (v1 - default).

  This reverses the encoding done by `encode/1` or `encode_v1/1`. The Doc is required
  to associate the decoded StickyIndex with its document context.
  """
  @spec decode(Doc.t(), binary()) :: t
  def decode(%Doc{} = doc, binary) when is_binary(binary) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_decode(doc, binary))
  end

  @doc """
  Decodes a StickyIndex from binary flexbuffer format (v1).
  """
  @spec decode_v1(Doc.t(), binary()) :: t
  def decode_v1(%Doc{} = doc, binary) when is_binary(binary) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_decode_v1(doc, binary))
  end

  @doc """
  Decodes a StickyIndex from JSON string format (v2).

  This reverses the encoding done by `encode_v2/1`. The Doc is required to associate
  the decoded StickyIndex with its document context.
  """
  @spec decode_v2(Doc.t(), binary()) :: t
  def decode_v2(%Doc{} = doc, binary) when is_binary(binary) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_decode_v2(doc, binary))
  end

  @doc """
  Gets the association direction of a StickyIndex.

  ## Returns

  - `-1` for `:before` association
  - `0` for `:after` association
  """
  @spec assoc(t) :: -1 | 0
  def assoc(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_assoc(sticky_index))
  end

  @doc """
  Converts a StickyIndex to JSON representation.

  Returns a serialized JSON string with StickyIndex position and association information in a format
  compatible with Yjs RelativePosition and yffi's ysticky_index_to_json.

  ## Returns

  A JSON string containing an object with:
  - Exactly one of `"item"`, `"type"`, or `"tname"`
  - `"item"` - `{"client": u64, "clock": u32}` for relative positions in existing content
  - `"type"` - `{"client": u64, "clock": u32}` for nested empty-type positions
  - `"tname"` - Type name string for root-level empty-type positions
  - `"assoc"` - Association value: `-1` for `:before`, `0` for `:after`
  """
  @spec to_json(t) :: String.t()
  def to_json(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc, do: Yex.Nif.sticky_index_to_json(sticky_index))
  end

  @doc """
  Reconstructs a StickyIndex from JSON representation.

  This delegates to the reconstruction NIF (`Yex.Nif.sticky_index_from_json/2`).

  ## Input constraints

  - `json` must be a binary JSON payload in StickyIndex/RelativePosition format.
  - `doc` must be a `%Yex.Doc{}` associated with the reconstructed StickyIndex.

  ## Returns

  - `{:ok, sticky_index}` when reconstruction succeeds
  - `{:error, reason}` when reconstruction fails (for example `:invalid_json`)
  """
  @spec from_json(String.t(), Doc.t()) :: {:ok, t} | {:error, atom()}
  def from_json(json, %Doc{} = doc) when is_binary(json) do
    Doc.run_in_worker_process(doc,
      do:
        case Yex.Nif.sticky_index_from_json(json, doc) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    )
  end

  @doc false
  # Gets the current transaction reference from the process dictionary for the given document
  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end
end
