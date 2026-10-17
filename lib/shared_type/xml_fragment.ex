defmodule Yex.XmlFragment do
  @moduledoc """
  A shared type to manage a collection of XML nodes.
  Provides functionality for manipulating XML fragments including child nodes and navigation.

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
  Returns the first child node of the XML fragment.
  Returns nil if the fragment has no children.
  """
  def first_child(%__MODULE__{} = xml_fragment) do
    fetch(xml_fragment, 0)
    |> case do
      {:ok, node} -> node
      :error -> nil
    end
  end

  @doc """
  Returns a stream of all child nodes of the XML fragment.

  A child that is not an XML node (for example a `Y.Map` a yjs peer inserted into
  the fragment) ends the stream: yrs `Xml::siblings` stops there, so later children
  are not returned.
  """
  @spec children(t) :: Enumerable.t(Yex.XmlElement.t() | Yex.XmlText.t())
  def children(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do:
        Stream.unfold(first_child(xml_fragment), fn
          nil -> nil
          xml -> {xml, Xml.next_sibling(xml)}
        end)
    )
  end

  # The nodes children/1 streams, read in one NIF call. Call it in the worker process.
  defp child_list(%__MODULE__{} = xml_fragment) do
    txn = cur_txn(xml_fragment)

    case Yex.Nif.xml_fragment_children(xml_fragment, txn, Yex.Nif.dirty_xml_children()) do
      :dirty -> Yex.Nif.xml_fragment_children_dirty(xml_fragment, txn)
      children -> children
    end
  end

  @typedoc "A node returned by `tree_walker/2`."
  @type xml_node :: Yex.XmlElement.t() | Yex.XmlText.t() | Yex.XmlFragment.t()

  @doc """
  Returns every descendant node of this fragment as a list, in document order
  (depth-first, pre-order), excluding the fragment itself. Unlike `children/1`,
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
      iex> Yex.XmlFragment.tree_walker(xml) |> Enum.map(&to_string/1)
      []
  """
  @spec tree_walker(t) :: [xml_node()]
  @spec tree_walker(t, (xml_node() -> as_boolean(term()))) :: [xml_node()]
  def tree_walker(%__MODULE__{doc: doc} = xml_fragment, filter \\ fn _ -> true end) do
    Doc.run_in_worker_process doc do
      xml_fragment
      |> Yex.Nif.xml_fragment_tree_walker(cur_txn(xml_fragment))
      |> Enum.filter(filter)
    end
  end

  @doc """
  Returns the first descendant `Yex.XmlElement` whose tag equals `tag`, compared
  case-insensitively, in document order, or `nil`. Only tag names are supported,
  as in yjs `querySelector`.
  """
  @spec query_selector(t, String.t()) :: Yex.XmlElement.t() | nil
  def query_selector(%__MODULE__{doc: doc} = xml_fragment, tag) do
    Doc.run_in_worker_process(doc,
      do:
        xml_fragment
        |> Yex.Nif.xml_fragment_query_selector(cur_txn(xml_fragment), tag, true)
        |> List.first()
    )
  end

  @doc """
  Returns every descendant `Yex.XmlElement` whose tag equals `tag`, compared
  case-insensitively, in document order. Only tag names are supported, as in yjs
  `querySelectorAll`.
  """
  @spec query_selector_all(t, String.t()) :: [Yex.XmlElement.t()]
  def query_selector_all(%__MODULE__{doc: doc} = xml_fragment, tag) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_query_selector(xml_fragment, cur_txn(xml_fragment), tag, false)
    )
  end

  @doc """
  Returns the parent node of this fragment.
  Returns nil if this is a top-level XML fragment.
  """
  @spec parent(t) :: Yex.XmlElement.t() | Yex.XmlFragment.t() | nil
  def parent(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_parent(xml_fragment, cur_txn(xml_fragment))
    )
  end

  @doc """
  Returns the number of child nodes in the XML fragment.
  """
  def length(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_length(xml_fragment, cur_txn(xml_fragment))
    )
  end

  @doc """
  Inserts a new child node at the specified index.
  Returns :ok on success, :error on failure.
  """
  def insert(%__MODULE__{doc: doc} = xml_fragment, index, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_insert(xml_fragment, cur_txn(xml_fragment), index, content)
    )
  end

  @doc """
  Inserts a new child node at the specified index and returns the inserted node.
  Returns the inserted node on success, raises on failure.
  """
  @spec insert_and_get(
          t,
          integer(),
          Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()
        ) :: Yex.XmlElement.t() | Yex.XmlText.t()
  def insert_and_get(%__MODULE__{doc: doc} = xml_fragment, index, content) do
    Doc.run_in_worker_process doc do
      Yex.Nif.xml_fragment_insert_and_get(xml_fragment, cur_txn(xml_fragment), index, content)
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
  def insert_after(%__MODULE__{doc: doc} = xml_fragment, ref, content) do
    Doc.run_in_worker_process doc do
      index = child_list(xml_fragment) |> Enum.find_index(&(&1 == ref))

      if index == nil do
        insert(xml_fragment, 0, content)
      else
        insert(xml_fragment, index + 1, content)
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
  def insert_after_and_get(%__MODULE__{doc: doc} = xml_fragment, ref, content) do
    Doc.run_in_worker_process doc do
      index = child_list(xml_fragment) |> Enum.find_index(&(&1 == ref))

      target_index =
        if index == nil do
          0
        else
          index + 1
        end

      Yex.Nif.xml_fragment_insert_and_get(
        xml_fragment,
        cur_txn(xml_fragment),
        target_index,
        content
      )
    end
  end

  @doc """
  Deletes a range of child nodes starting at the specified index.
  Returns :ok on success, :error on failure.
  """
  def delete(%__MODULE__{doc: doc} = xml_fragment, index, length) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_delete_range(xml_fragment, cur_txn(xml_fragment), index, length)
    )
  end

  @doc """
  Appends a new child node at the end of the children list.
  Returns :ok on success, :error on failure.
  """
  def push(xml_fragment, content) do
    insert(xml_fragment, @u32_max, content)
  end

  @doc """
  Appends a new child node at the end of the children list and returns the inserted node.
  Returns the inserted node on success, raises on failure.
  """
  @spec push_and_get(
          t,
          Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()
        ) :: Yex.XmlElement.t() | Yex.XmlText.t()
  def push_and_get(xml_fragment, content) do
    insert_and_get(xml_fragment, @u32_max, content)
  end

  @doc """
  Inserts a new child node at the beginning of the children list.
  Returns :ok on success, :error on failure.
  """
  def unshift(%__MODULE__{} = xml_fragment, content) do
    insert(xml_fragment, 0, content)
  end

  @doc """
  Gets a child node by index from the XML fragment, or returns the default value if the index is out of bounds.

  ## Parameters
    * `xml_fragment` - The XML fragment to query
    * `index` - The index to look up
    * `default` - The default value to return if index is out of bounds (defaults to nil)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.push(xml, Yex.XmlElementPrelim.empty("div"))
      iex> elem = Yex.XmlFragment.get(xml, 0)
      iex> match?(%Yex.XmlElement{}, elem)
      true
      iex> Yex.XmlFragment.get(xml, 10)
      nil
      iex> Yex.XmlFragment.get(xml, 10, :not_found)
      :not_found
  """
  @spec get(t, integer(), default :: term()) :: Yex.XmlElement.t() | Yex.XmlText.t() | term()
  def get(%__MODULE__{} = xml_fragment, index, default \\ nil) do
    case fetch(xml_fragment, index) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Gets a child node by index from the XML fragment, or lazily evaluates the given function if the index is out of bounds.
  This is useful when the default value is expensive to compute and should only be evaluated when needed.

  ## Parameters
    * `xml_fragment` - The XML fragment to query
    * `index` - The index to look up
    * `fun` - A function that returns the default value (only called if index is out of bounds)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.push(xml, Yex.XmlTextPrelim.from("Hello"))
      iex> Yex.XmlFragment.get_lazy(xml, 0, fn -> Yex.XmlFragment.push_and_get(xml, Yex.XmlTextPrelim.from("Computed")) end) |> to_string()
      "Hello"
      iex> Yex.XmlFragment.get_lazy(xml, 10, fn -> Yex.XmlFragment.push_and_get(xml, Yex.XmlTextPrelim.from("Computed")) end) |> to_string()
      "Computed"

  Particularly useful with `*_and_get` functions for get-or-create patterns:

      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> # Get existing node or create and return new one
      iex> node = Yex.XmlFragment.get_lazy(xml, 0, fn ->
      ...>   Yex.XmlFragment.push_and_get(xml, Yex.XmlElementPrelim.empty("div"))
      ...> end)
      iex> Yex.XmlElement.get_tag(node)
      "div"
  """
  @spec get_lazy(t, integer(), fun :: (-> term())) ::
          Yex.XmlElement.t() | Yex.XmlText.t() | term()
  def get_lazy(%__MODULE__{} = xml_fragment, index, fun) do
    case fetch(xml_fragment, index) do
      {:ok, value} -> value
      :error -> fun.()
    end
  end

  @doc """
  Retrieves the child node at the specified index.
  Returns {:ok, node} if found, :error if index is out of bounds.
  """
  @spec fetch(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def fetch(%__MODULE__{doc: doc} = xml_fragment, index) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_get(xml_fragment, cur_txn(xml_fragment), index)
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
  Returns a string representation of the XML fragment and all its child nodes.
  """
  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.xml_fragment_to_string(xml_fragment, cur_txn(xml_fragment))
    )
  end

  @doc """
  Converts the XML fragment to a preliminary representation.
  This is useful when you need to serialize or transfer the fragment's structure.
  """
  @spec as_prelim(t) :: Yex.XmlFragmentPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do:
        child_list(xml_fragment)
        |> Enum.map(fn child -> Yex.Output.as_prelim(child) end)
        |> Yex.XmlFragmentPrelim.new()
    )
  end

  defimpl Yex.Output do
    @doc """
    Converts an XmlFragment into its preliminary (serializable) representation.
    """
    @spec as_prelim(Yex.XmlFragment.t()) :: Yex.XmlFragmentPrelim.t()
    def as_prelim(xml_fragment) do
      Yex.XmlFragment.as_prelim(xml_fragment)
    end
  end

  defimpl String.Chars do
    @doc """
    Convert the XML fragment to its string representation.
    """
    @spec to_string(Yex.XmlFragment.t()) :: String.t()
    def to_string(xml_fragment), do: Yex.XmlFragment.to_string(xml_fragment)
  end
end

defmodule Yex.XmlFragmentPrelim do
  @moduledoc """
  A preliminary xml fragment. It can be used to early initialize the contents of a XmlFragment.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert(array, 0,  Yex.XmlFragmentPrelim.new([Yex.XmlElementPrelim.empty("div")]))
      iex> {:ok, %Yex.XmlFragment{} = fragment} = Yex.Array.fetch(array, 0)
      iex> Yex.XmlFragment.to_string(fragment)
      "<div></div>"

  """
  defstruct [:children]

  @type t :: %__MODULE__{
          children: [Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()]
        }

  @doc """
  Creates a new preliminary XML fragment with the given children.
  The children can be a mix of XmlElementPrelim and XmlTextPrelim nodes.

  ## Parameters
    * `children` - A list or enumerable of preliminary XML nodes (elements or text)

  ## Returns
    * A new XmlFragmentPrelim struct containing the provided children
  """
  def new(children) do
    %__MODULE__{
      children: Enum.to_list(children)
    }
  end
end
