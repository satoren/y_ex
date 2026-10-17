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
  import Yex.Doc, only: [cur_txn: 1]

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

  A child that is not an XML node (for example a `Y.Map` a yjs peer inserted into
  the fragment) ends the stream: yrs `Xml::siblings` stops there, so later children
  are not returned.
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

  # The nodes children/1 streams, read in one NIF call. Call it in the worker process.
  defp child_list(%__MODULE__{} = xml_element) do
    txn = cur_txn(xml_element)

    case Yex.Nif.xml_element_children(xml_element, txn, Yex.Nif.dirty_xml_children()) do
      :dirty -> Yex.Nif.xml_element_children_dirty(xml_element, txn)
      children -> children
    end
  end

  @typedoc "A node returned by `tree_walker/2`."
  @type xml_node :: Yex.XmlElement.t() | Yex.XmlText.t() | Yex.XmlFragment.t()

  @doc """
  Returns every descendant node of this element as a list, in document order
  (depth-first, pre-order), excluding the element itself. Unlike `children/1`,
  which returns a lazy `Stream`, this reads the whole subtree at once.

  The nodes are read in a single read transaction, or inside the open
  `Yex.Doc.transaction/2` if there is one, so the result is a consistent snapshot.

  When `filter` is given, only nodes for which it returns a truthy value are
  returned. The filter does not prune: descendants of a rejected element are
  still visited, as with yjs `createTreeWalker(filter)`. The filter runs in the
  document's worker process (`doc.worker_pid`) when that is another process, so
  `self()` inside it is the worker, as with the function given to `Yex.Doc.transaction/3`.

  A child that is not an XML node (for example a `Y.Map` a yjs peer inserted into
  the fragment) ends the walk: yrs `XmlFragment::successors` (`TreeWalker`) stops
  there, so later nodes are not returned.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> div = Yex.XmlFragment.push_and_get(xml, Yex.XmlElementPrelim.new("div", [Yex.XmlElementPrelim.new("p", [Yex.XmlTextPrelim.from("hi")])]))
      iex> Yex.XmlElement.tree_walker(div) |> Enum.map(&to_string/1)
      ["<p>hi</p>", "hi"]
  """
  @spec tree_walker(t) :: [xml_node()]
  @spec tree_walker(t, (xml_node() -> as_boolean(term()))) :: [xml_node()]
  def tree_walker(%__MODULE__{doc: doc} = xml_element, filter \\ fn _ -> true end) do
    Doc.run_in_worker_process doc do
      xml_element
      |> Yex.Nif.xml_element_tree_walker(cur_txn(xml_element))
      |> Enum.filter(filter)
    end
  end

  @doc """
  Returns the first descendant `Yex.XmlElement` whose tag equals `tag`, compared
  case-insensitively, in document order, or `nil`. Only tag names are supported,
  as in yjs `querySelector`.
  """
  @spec query_selector(t, String.t()) :: Yex.XmlElement.t() | nil
  def query_selector(%__MODULE__{doc: doc} = xml_element, tag) do
    Doc.run_in_worker_process(doc,
      do:
        xml_element
        |> Yex.Nif.xml_element_query_selector(cur_txn(xml_element), tag, true)
        |> List.first()
    )
  end

  @doc """
  Returns every descendant `Yex.XmlElement` whose tag equals `tag`, compared
  case-insensitively, in document order. Only tag names are supported, as in yjs
  `querySelectorAll`.
  """
  @spec query_selector_all(t, String.t()) :: [Yex.XmlElement.t()]
  def query_selector_all(%__MODULE__{doc: doc} = xml_element, tag) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_query_selector(xml_element, cur_txn(xml_element), tag, false)
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
      index = child_list(xml_element) |> Enum.find_index(&(&1 == ref))

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
      index = child_list(xml_element) |> Enum.find_index(&(&1 == ref))

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
  @spec insert_attribute(t, binary(), Yex.input_type()) :: :ok | :error
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
  @spec get_attribute(t, binary()) :: term()
  def get_attribute(%__MODULE__{doc: doc} = xml_element, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get_attribute(xml_element, cur_txn(xml_element), key)
    )
  end

  @doc """
  Returns a map of all attributes for this XML element.
  """
  @spec get_attributes(t) :: %{binary() => term()}
  def get_attributes(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_get_attributes(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  Returns true when the element has the attribute `key`, even if its value is nil.
  """
  @spec has_attribute?(t, binary()) :: boolean()
  def has_attribute?(%__MODULE__{} = xml_element, key) do
    Map.has_key?(get_attributes(xml_element), key)
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

  @doc """
  Returns the XML string representation of the element, including its children.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.push(xml, Yex.XmlElementPrelim.new("div", [Yex.XmlTextPrelim.from("text")]))
      iex> {:ok, element} = Yex.XmlFragment.fetch(xml, 0)
      iex> Yex.XmlElement.to_string(element)
      "<div>text</div>"
  """
  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_element_to_string(xml_element, cur_txn(xml_element))
    )
  end

  @doc """
  Converts the element, including its attributes and children, into a `Yex.XmlElementPrelim`.

  The result can be inserted elsewhere to copy the element. Attribute values that are
  shared types are copied as prelims too, like the values of `Yex.Map.as_prelim/1`.
  """
  @spec as_prelim(t) :: Yex.XmlElementPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = xml_element) do
    Doc.run_in_worker_process doc do
      c =
        child_list(xml_element)
        |> Enum.map(fn child -> Yex.Output.as_prelim(child) end)

      attributes =
        Map.new(get_attributes(xml_element), fn {k, v} -> {k, Yex.Output.as_prelim(v)} end)

      Yex.XmlElementPrelim.new(get_tag(xml_element), c, attributes)
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
    defdelegate get_attribute(xml, key), to: Yex.XmlElement
    defdelegate get_attributes(xml), to: Yex.XmlElement
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
          attributes: %{binary() => Yex.input_type()},
          children: [Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()]
        }

  @doc """
  Creates a preliminary xml element with the given tag, children and attributes.
  """
  @spec new(String.t(), Enumerable.t(), %{String.t() => String.t() | Yex.PrelimType.t()}) :: t
  def new(tag, children, attributes \\ %{}) do
    %__MODULE__{
      tag: tag,
      attributes: attributes,
      children: Enum.to_list(children)
    }
  end

  @doc """
  Creates a preliminary xml element with the given tag and no children or attributes.
  """
  @spec empty(String.t()) :: t
  def empty(tag) do
    %__MODULE__{
      tag: tag,
      attributes: %{},
      children: []
    }
  end
end
