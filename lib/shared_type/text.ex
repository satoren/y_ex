defmodule Yex.Text do
  @moduledoc """
  A shareable type that is optimized for shared editing on text.
  This module provides functionality for collaborative text editing with support for rich text formatting.

  ## Features
  - Insert and delete text at any position
  - Apply formatting attributes (bold, italic, etc.)
  - Support for Quill Delta format for change tracking
  - Collaborative editing with conflict resolution
  """
  defstruct [
    :doc,
    :reference
  ]

  alias Yex.Doc
  require Yex.Doc

  @type delta ::
          [%{:insert => binary(), optional(:attributes) => map()}]
          | [%{delete: integer()}]
          | [%{:retain => integer(), optional(:attributes) => map()}]
  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @doc """
  Inserts text content at the specified index.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `text` - The text object to modify
    * `index` - The position to insert at (0-based)
    * `content` - The text content to insert
  """
  @spec insert(t, integer(), binary()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = text, index, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_insert(text, cur_txn(text), index, content)
    )
  end

  @doc """
  Inserts text content with formatting attributes at the specified index.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `text` - The text object to modify
    * `index` - The position to insert at (0-based)
    * `content` - The text content to insert
    * `attr` - A map of formatting attributes to apply (e.g. %{"bold" => true})
  """
  @spec insert(t, integer(), binary(), map()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = text, index, content, attr) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_insert_with_attributes(text, cur_txn(text), index, content, attr)
    )
  end

  @doc """
  Deletes text content starting at the specified index.
  Supports negative indices for deletion from the end.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `text` - The text object to modify
    * `index` - The starting position to delete from (0-based, negative indices count from end)
    * `length` - The number of characters to delete
  """
  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{doc: doc} = text, index, length) do
    Doc.run_in_worker_process doc do
      Yex.Nif.text_delete(text, cur_txn(text), index, length)
    end
  end

  @doc """
  Applies formatting attributes to a range of text.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `text` - The text object to modify
    * `index` - The starting position to format from (0-based)
    * `length` - The number of characters to format
    * `attr` - A map of formatting attributes to apply (e.g. %{"bold" => true})
  """
  @spec format(t, integer(), integer(), map()) :: :ok | :error
  def format(%__MODULE__{doc: doc} = text, index, length, attr) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_format(text, cur_txn(text), index, length, attr)
    )
  end

  @doc """
  Returns the text content as a string.

  ## Parameters
    * `text` - The text object to convert to string
  """
  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_to_string(text, cur_txn(text))
    )
  end

  @doc """
  Returns the length of the text content in characters.

  ## Parameters
    * `text` - The text object to get the length of
  """
  @spec length(t) :: integer()
  def length(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_length(text, cur_txn(text))
    )
  end

  @doc """
  Converts the text object to its preliminary representation.
  This is useful when you need to serialize or transfer the text content and formatting.

  ## Parameters
    * `text` - The text object to convert
  """
  @spec as_prelim(t) :: Yex.TextPrelim.t()
  def as_prelim(%__MODULE__{} = text) do
    Yex.Text.to_delta(text) |> Yex.TextPrelim.from()
  end

  defimpl Yex.Output do
    @doc """
    Converts the given text into a preliminary `Yex.TextPrelim` representation.
    """
    @spec as_prelim(Yex.Text.t()) :: Yex.TextPrelim.t()
    def as_prelim(text) do
      Yex.Text.as_prelim(text)
    end
  end

  defimpl String.Chars do
    @doc """
Convert a Yex.Text value into its textual content.
"""
@spec to_string(Yex.Text.t()) :: String.t()
def to_string(text), do: Yex.Text.to_string(text)
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples Syncs two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> delta = [%{ "retain" => 1}, %{ "delete" => 3}]
      iex> Yex.Text.insert(text,0, "12345")
      iex> Yex.Text.apply_delta(text,delta)
      iex> Yex.Text.to_delta(text)
      [%{insert: "15"}]
  """
  @spec apply_delta(t, delta) :: :ok | :error
  def apply_delta(%__MODULE__{doc: doc} = text, delta) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_apply_delta(text, cur_txn(text), delta)
    )
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples creates a few changes, then gets them back as a batch of change maps
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "12345")
      iex> Yex.Text.insert(text, 0, "0", %{"bold" => true})
      iex> Yex.Text.to_delta(text)
      [%{insert: "0", attributes: %{"bold" => true}}, %{insert: "12345"}]
  """
  @spec to_delta(t) :: delta()
  def to_delta(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_to_delta(text, cur_txn(text))
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end
end

defmodule Yex.TextPrelim do
  @moduledoc """
  A preliminary text representation used for initializing text content.
  This module provides functionality for creating text content with formatting
  before it is inserted into a shared document.

  ## Use Cases
  - Creating formatted text content before inserting into a document
  - Serializing text content for transfer between documents
  - Initializing text content with specific formatting attributes

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from("Hello World"))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello World"}]
  """
  defstruct [
    :delta
  ]

  @type t :: %__MODULE__{
          delta: Yex.Text.delta()
        }

  @doc """
  Creates a new TextPrelim from either a binary string or a delta format.

  ## Examples with a binary string
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from("Hello World"))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello World"}]

  ## Examples with formatted delta
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from([%{insert: "Hello"},%{insert: " World", attributes: %{ "bold" => true }},]))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello"}, %{attributes: %{"bold" => true}, insert: " World"}]

  ## Parameters
    * `text` - Either a binary string or a delta format array
  """
  @spec from(binary()) :: t
  def from(text) when is_binary(text) do
    %__MODULE__{delta: [%{insert: text}]}
  end

  @spec from(Yex.Text.delta()) :: t
  def from(delta) do
    %__MODULE__{delta: delta}
  end
end