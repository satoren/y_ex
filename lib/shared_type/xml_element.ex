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

  @u32_max 2 ** 32 - 1
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
  Inserts a new child node at the specified index and returns the inserted node.
  Returns the inserted node on success, raises on failure.

  """
  @spec insert_and_get(t, integer(), Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) ::
          Yex.XmlElement.t() | Yex.XmlText.t()
  def insert_and_get(%__MODULE__{doc: doc} = xml_element, index, content) do
    Doc.run_in_worker_process doc do
      Yex.Nif.xml_element_insert_and_get(xml_element, cur_txn(xml_element), index, content)
    end
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
  Inserts a new child node after the specified reference node and returns the inserted node.
  If the reference node is not found, inserts at the beginning.
  Returns the inserted node on success, raises on failure.

  """
  @spec insert_after_and_get(
          t,
          Yex.XmlElement.t() | Yex.XmlText.t(),
          Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()
        ) :: Yex.XmlElement.t() | Yex.XmlText.t()
  def insert_after_and_get(%__MODULE__{doc: doc} = xml_element, ref, content) do
    Doc.run_in_worker_process doc do
      index = children(xml_element) |> Enum.find_index(&(&1 == ref))

      target_index =
        if index == nil do
          0
        else
          index + 1
        end

      insert_and_get(xml_element, target_index, content)
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
  def push(xml_element, content) do
    insert(xml_element, @u32_max, content)
  end

  @doc """
  Appends a new child node at the end of the children list and returns the inserted node.
  Returns the inserted node on success, raises on failure.
  """
  @spec push_and_get(t, Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) ::
          Yex.XmlElement.t() | Yex.XmlText.t()
  def push_and_get(xml_element, content) do
    insert_and_get(xml_element, @u32_max, content)
  end

  @doc """
  Inserts a new child node at the beginning of the children list.
  Returns :ok on success, :error on failure.
  """
  @spec unshift(t, Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()) :: :ok | :error
  def unshift(%__MODULE__{} = xml_element, content) do
    insert(xml_element, 0, content)
  end

  @doc """
  Gets a child node by index from the XML element, or returns the default value if the index is out of bounds.

  ## Parameters
    * `xml_element` - The XML element to query
    * `index` - The index to look up
    * `default` - The default value to return if index is out of bounds (defaults to nil)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> elem = Yex.XmlFragment.push_and_get(xml, Yex.XmlElementPrelim.empty("div"))
      iex> Yex.XmlElement.push(elem, Yex.XmlTextPrelim.from("content"))
      iex> text = Yex.XmlElement.get(elem, 0)
      iex> match?(%Yex.XmlText{}, text)
      true
      iex> Yex.XmlElement.get(elem, 10)
      nil
      iex> Yex.XmlElement.get(elem, 10, :not_found)
      :not_found
  """
  @spec get(t, integer(), default :: term()) :: Yex.XmlElement.t() | Yex.XmlText.t() | term()
  def get(%__MODULE__{} = xml_element, index, default \\ nil) do
    case fetch(xml_element, index) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Gets a child node by index from the XML element, or lazily evaluates the given function if the index is out of bounds.
  This is useful when the default value is expensive to compute and should only be evaluated when needed.

  ## Parameters
    * `xml_element` - The XML element to query
    * `index` - The index to look up
    * `fun` - A function that returns the default value (only called if index is out of bounds)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> elem = Yex.XmlFragment.push_and_get(xml, Yex.XmlElementPrelim.empty("div"))
      iex> Yex.XmlElement.push(elem, Yex.XmlTextPrelim.from("Hello"))
      iex> Yex.XmlElement.get_lazy(elem, 0, fn -> Yex.XmlElement.push_and_get(elem, Yex.XmlTextPrelim.from("Computed")) end) |> to_string()
      "Hello"
      iex> Yex.XmlElement.get_lazy(elem, 10, fn -> Yex.XmlElement.push_and_get(elem, Yex.XmlTextPrelim.from("Computed")) end) |> to_string()
      "Computed"

  Particularly useful with `*_and_get` functions for get-or-create patterns:

      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> elem = Yex.XmlFragment.push_and_get(xml, Yex.XmlElementPrelim.empty("div"))
      iex> # Get existing child or create and return new one
      iex> child = Yex.XmlElement.get_lazy(elem, 0, fn ->
      ...>   Yex.XmlElement.push_and_get(elem, Yex.XmlElementPrelim.empty("span"))
      ...> end)
      iex> Yex.XmlElement.get_tag(child)
      "span"
  """
  @spec get_lazy(t, integer(), fun :: (-> term())) ::
          Yex.XmlElement.t() | Yex.XmlText.t() | term()
  def get_lazy(%__MODULE__{} = xml_element, index, fun) do
    case fetch(xml_element, index) do
      {:ok, value} -> value
      :error -> fun.()
    end
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

  @spec observe(
          t,
          handler :: (update :: Yex.XmlEvent.t(), origin :: term() -> nil)
        ) :: reference()
  def observe(%__MODULE__{doc: doc} = xml_element, handler) do
    Yex.SharedType.observe(xml_element,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
    )
  end

  @spec observe_deep(
          t,
          handler :: (update :: list(Yex.event_type()), origin :: term() -> nil)
        ) :: reference()
  def observe_deep(%__MODULE__{doc: doc} = xml_element, handler) do
    Yex.SharedType.observe_deep(xml_element,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
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

  defimpl String.Chars do
    @doc """
    Converts the given XML element to its textual XML representation.
    """
    @spec to_string(Yex.XmlElement.t()) :: String.t()
    def to_string(xml_element), do: Yex.XmlElement.to_string(xml_element)
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
