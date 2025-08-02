defmodule Yex.XmlElement do
  @moduledoc """
  A shared type that represents an XML node.
  Provides functionality for manipulating XML elements including child nodes, attributes, and navigation.

  """

  alias Yex.Xml

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

  @doc """
  Returns the first child node of the XML element.
  Returns nil if the element has no children.
  """
  @spec first_child(t) :: Yex.XmlElement.t() | Yex.XmlText.t() | nil
  def first_child(%__MODULE__{} = xml_element) do
    fetch(xml_element, 0)
    |> case do
      {:ok, node} -> node
      :error -> nil
    end
  end

  @doc """
  Returns a stream of all child nodes of the XML element.
  """
  @spec children(t) :: Enumerable.t(Yex.XmlElement.t() | Yex.XmlText.t())
  def children(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do:
        Stream.unfold(first_child(xml_element), fn
          nil -> nil
          xml -> {xml, Xml.next_sibling(xml)}
        end)
    )
  end

  @doc """
  Returns the number of child nodes in the XML element.
  """
  @spec length(t) :: integer()
  def length(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_length(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  Inserts a new child node at the specified index.
  Returns :ok on success, :error on failure.
  """
  @spec insert(t, integer(), Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = xml_element, index, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_insert(xml_element, cur_txn(xml_element), index, content)
    )
  end

  @doc """
  Inserts a new child node after the specified reference node.
  If the reference node is not found, inserts at the beginning.
  Returns :ok on success, :error on failure.
  """
  @spec insert_after(
          t,
          Yex.XmlElement.t() | Yex.XmlText.t(),
          Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()
        ) :: :ok | :error
  def insert_after(%__MODULE__{doc: doc} = xml_element, ref, content) do
    Doc.run_in_worker_process doc do
      index = children(xml_element) |> Enum.find_index(&(&1 == ref))

      if index == nil do
        insert(xml_element, 0, content)
      else
        insert(xml_element, index + 1, content)
      end
    end
  end

  @doc """
  Deletes a range of child nodes starting at the specified index.
  Returns :ok on success, :error on failure.
  """
  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{doc: doc} = xml_element, index, length) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_delete_range(xml_element, cur_txn(xml_element), index, length)
    )
  end

  @doc """
  Appends a new child node at the end of the children list.
  Returns :ok on success, :error on failure.
  """
  @spec push(t, Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) :: :ok | :error
  def push(%__MODULE__{doc: doc} = xml_element, content) do
    Doc.run_in_worker_process(doc,
      do: insert(xml_element, __MODULE__.length(xml_element), content)
    )
  end

  @doc """
  Inserts a new child node at the beginning of the children list.
  Returns :ok on success, :error on failure.
  """
  @spec unshift(t, Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) :: :ok | :error
  def unshift(%__MODULE__{} = xml_element, content) do
    insert(xml_element, 0, content)
  end

  @deprecated "Rename to `fetch/2`"
  @spec get(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def get(%__MODULE__{} = xml_element, index) do
    fetch(xml_element, index)
  end

  @doc """
  Retrieves the child node at the specified index.
  Returns {:ok, node} if found, :error if index is out of bounds.
  """
  @spec fetch(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def fetch(%__MODULE__{doc: doc} = xml_element, index) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get(xml_element, cur_txn(xml_element), index)
    )
  end

  @doc """
  Similar to fetch/2 but raises ArgumentError if the index is out of bounds.
  """
  @spec fetch!(t, integer()) :: Yex.XmlElement.t() | Yex.XmlText.t()
  def fetch!(%__MODULE__{} = map, index) do
    case fetch(map, index) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Index out of bounds"
    end
  end

  @doc """
  Adds or updates an attribute with the specified key and value.
  Returns :ok on success, :error on failure.
  """
  @spec insert_attribute(t, binary(), binary() | Yex.PrelimType.t()) :: :ok | :error
  def insert_attribute(%__MODULE__{doc: doc} = xml_element, key, value) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_insert_attribute(xml_element, cur_txn(xml_element), key, value)
    )
  end

  @doc """
  Removes the attribute with the specified key.
  Returns :ok on success, :error on failure.
  """
  @spec remove_attribute(t, binary()) :: :ok | :error
  def remove_attribute(%__MODULE__{doc: doc} = xml_element, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_remove_attribute(xml_element, cur_txn(xml_element), key)
    )
  end

  @doc """
  Returns the tag name of the XML element.
  Returns nil if the element has no tag.
  """
  @spec get_tag(t) :: binary() | nil
  def get_tag(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get_tag(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  Returns the value of the specified attribute.
  Returns nil if the attribute does not exist.
  """
  @spec get_attribute(t, binary()) :: binary() | Yex.SharedType.t() | nil
  def get_attribute(%__MODULE__{doc: doc} = xml_element, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get_attribute(xml_element, cur_txn(xml_element), key)
    )
  end

  @doc """
  Returns a map of all attributes for this XML element.
  """
  @spec get_attributes(t) :: %{binary() => binary() | Yex.SharedType.t()}
  def get_attributes(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get_attributes(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  The next sibling of this type. Is null if this is the last child of its parent.
  """
  @spec next_sibling(t) :: Yex.XmlElement.t() | Yex.XmlText.t() | nil
  def next_sibling(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_next_sibling(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  The previous sibling of this type. Is null if this is the first child of its parent.
  """
  @spec prev_sibling(t) :: Yex.XmlElement.t() | Yex.XmlText.t() | nil
  def prev_sibling(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_prev_sibling(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  The parent that holds this type. Is null if this xml is a top-level XML type.
  """
  @spec parent(t) :: Yex.XmlElement.t() | Yex.XmlFragment.t() | nil
  def parent(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_parent(xml_element, cur_txn(xml_element))
    )
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_to_string(xml_element, cur_txn(xml_element))
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @spec as_prelim(t) :: Yex.XmlElementPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process doc do
      c =
        children(xml_element)
        |> Enum.map(fn child -> Yex.Output.as_prelim(child) end)

      Yex.XmlElementPrelim.new(
        get_tag(xml_element),
        c,
        get_attributes(xml_element)
      )
    end
  end

  defimpl Yex.Output do
    def as_prelim(xml_element) do
      Yex.XmlElement.as_prelim(xml_element)
    end
  end

  defimpl Yex.Xml do
    defdelegate next_sibling(xml), to: Yex.XmlElement
    defdelegate prev_sibling(xml), to: Yex.XmlElement
    defdelegate parent(xml), to: Yex.XmlElement
    defdelegate to_string(xml), to: Yex.XmlElement
  end
end

defmodule Yex.XmlElementPrelim do
  @moduledoc """
  A preliminary xml element. It can be used to early initialize the contents of a XmlElement.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.insert(xml, 0,  Yex.XmlElementPrelim.empty("div"))
      iex> Yex.XmlFragment.to_string(xml)
      "<div></div>"

  """
  defstruct [:tag, :attributes, :children]

  @type t :: %__MODULE__{
          tag: String.t(),
          attributes: %{String.t() => String.t() | Yex.PrelimType.t()},
          children: [Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()]
        }

  def new(tag, children, attributes \\ %{}) do
    %__MODULE__{
      tag: tag,
      attributes: attributes,
      children: Enum.to_list(children)
    }
  end

  def empty(tag) do
    %__MODULE__{
      tag: tag,
      attributes: %{},
      children: []
    }
  end
end
