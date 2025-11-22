defmodule Yex.XmlText do
  @moduledoc """
  A shared type that represents an XML text node.
  Extends Y.Text to provide functionality for manipulating text content within XML nodes,
  including text formatting and navigation.
  """

  defstruct [
    :doc,
    :reference
  ]

  alias Yex.Doc
  require Yex.Doc

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @type delta :: Yex.Text.delta()

  @doc """
  Inserts text content at the specified index.
  Returns :ok on success, :error on failure.
  """
  @spec insert(t, integer(), Yex.input_type()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = xml_text, index, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_insert(xml_text, cur_txn(xml_text), index, content)
    )
  end

  @doc """
  Inserts text content with attributes at the specified index.
  Returns :ok on success, :error on failure.
  """
  @spec insert(t, integer(), Yex.input_type(), map()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = xml_text, index, content, attr) do
    Doc.run_in_worker_process(doc,
      do:
        Yex.Nif.xml_text_insert_with_attributes(xml_text, cur_txn(xml_text), index, content, attr)
    )
  end

  @doc """
  Deletes text content starting at the specified index.
  Supports negative indices for deletion from the end.
  Returns :ok on success, :error on failure.
  """
  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{doc: doc} = xml_text, index, length) do
    Doc.run_in_worker_process doc do
      Yex.Nif.xml_text_delete(xml_text, cur_txn(xml_text), index, length)
    end
  end

  @doc """
  Applies formatting attributes to a range of text.
  Returns :ok on success, :error on failure.
  """
  @spec format(t, integer(), integer(), map()) :: :ok | :error
  def format(%__MODULE__{doc: doc} = xml_text, index, length, attr) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_format(xml_text, cur_txn(xml_text), index, length, attr)
    )
  end

  @doc """
  Applies a delta of changes to the text content.
  Returns :ok on success, :error on failure.
  """
  @spec apply_delta(t, delta) :: :ok | :error
  def apply_delta(%__MODULE__{doc: doc} = xml_text, delta) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_apply_delta(xml_text, cur_txn(xml_text), delta)
    )
  end

  @doc """
  Returns the text content as a delta format, including any formatting attributes.
  """
  def to_delta(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_to_delta(xml_text, cur_txn(xml_text))
    )
  end

  @doc """
  Returns the text content as a string, including any formatting tags.
  """
  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_to_string(xml_text, cur_txn(xml_text))
    )
  end

  @doc """
  Returns the length of the text content.
  """
  @spec length(t) :: integer()
  def length(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_length(xml_text, cur_txn(xml_text))
    )
  end

  @doc """
  Returns the next sibling node of this text node.
  Returns nil if this is the last child of its parent.
  """
  @spec next_sibling(t) :: Yex.XmlElement.t() | Yex.XmlText.t() | nil
  def next_sibling(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_next_sibling(xml_text, cur_txn(xml_text))
    )
  end

  @doc """
  Returns the previous sibling node of this text node.
  Returns nil if this is the first child of its parent.
  """
  @spec prev_sibling(t) :: Yex.XmlElement.t() | Yex.XmlText.t() | nil
  def prev_sibling(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_prev_sibling(xml_text, cur_txn(xml_text))
    )
  end

  @doc """
  Returns the parent node of this text node.
  Returns nil if this is a top-level XML node.
  """
  @spec parent(t) :: Yex.XmlElement.t() | Yex.XmlFragment.t() | nil
  def parent(%__MODULE__{doc: doc} = xml_text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_text_parent(xml_text, cur_txn(xml_text))
    )
  end

  @doc false
  # Gets the current transaction reference from the process dictionary for the given document
  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @doc """
  Converts the XML text node to a preliminary representation.
  This is useful when you need to serialize or transfer the text node's content and formatting.
  """
  @spec as_prelim(t) :: Yex.XmlTextPrelim.t()
  def as_prelim(%__MODULE__{} = xml_text) do
    Yex.XmlTextPrelim.from(to_delta(xml_text))
  end

  defimpl Yex.Output do
    @doc """
    Implementation of the Yex.Output protocol for XmlText.
    Converts the XML text node to its preliminary representation.
    """
    def as_prelim(xml_text) do
      Yex.XmlText.as_prelim(xml_text)
    end
  end

  defimpl Yex.Xml do
    @doc """
    Implementation of the Yex.Xml protocol for XmlText.
    Delegates XML node operations to the XmlText module functions.
    """
    defdelegate next_sibling(xml), to: Yex.XmlText
    defdelegate prev_sibling(xml), to: Yex.XmlText
    defdelegate parent(xml), to: Yex.XmlText
    defdelegate to_string(xml), to: Yex.XmlText
  end

  defimpl String.Chars do
    @doc """
Converts an XML text node to its string representation including formatting tags.
"""
@spec to_string(Yex.XmlText.t()) :: String.t()
def to_string(xml_text), do: Yex.XmlText.to_string(xml_text)
  end
end

defmodule Yex.XmlTextPrelim do
  @moduledoc """
  A preliminary xml text. It can be used to early initialize the contents of a XmlText.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.insert(xml, 0,  Yex.XmlTextPrelim.from("Hello World"))
      iex> {:ok, %Yex.XmlText{} = text} = Yex.XmlFragment.fetch(xml, 0)
      iex> Yex.XmlText.to_delta(text)
      [%{insert: "Hello World"}]

  """
  defstruct [
    :delta,
    :attributes
  ]

  @type t :: %__MODULE__{
          delta: Yex.Text.delta(),
          attributes: %{binary() => binary()}
        }

  @doc """
  Transforms a Text to a TextPrelim
  ## Examples with a binary
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.XmlTextPrelim.from("Hello World"))
      iex> {:ok, %Yex.XmlText{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.XmlText.to_delta(text)
      [%{insert: "Hello World"}]


  ## Examples with delta
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.XmlTextPrelim.from([%{insert: "Hello"},%{insert: " World", attributes: %{ "bold" => true }},]))
      iex> {:ok,%Yex.XmlText{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.XmlText.to_delta(text)
      [%{insert: "Hello"}, %{attributes: %{"bold" => true}, insert: " World"}]
  """
  @spec from(binary()) :: t
  def from(text) when is_binary(text) do
    %__MODULE__{delta: [%{insert: text}], attributes: %{}}
  end

  @spec from(Yex.Text.delta()) :: t
  def from(delta) do
    %__MODULE__{delta: delta, attributes: %{}}
  end
end