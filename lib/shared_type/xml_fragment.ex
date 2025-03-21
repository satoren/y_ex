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

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

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
      index = children(xml_fragment) |> Enum.find_index(&(&1 == ref))

      if index == nil do
        insert(xml_fragment, 0, content)
      else
        insert(xml_fragment, index + 1, content)
      end
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
  def push(%__MODULE__{doc: doc} = xml_fragment, content) do
    Doc.run_in_worker_process(doc,
      do: insert(xml_fragment, __MODULE__.length(xml_fragment), content)
    )
  end

  @doc """
  Inserts a new child node at the beginning of the children list.
  Returns :ok on success, :error on failure.
  """
  def unshift(%__MODULE__{} = xml_fragment, content) do
    insert(xml_fragment, 0, content)
  end

  @deprecated "Rename to `fetch/2`"
  @spec get(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def get(%__MODULE__{} = xml_fragment, index) do
    fetch(xml_fragment, index)
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

  @doc false
  # Gets the current transaction reference from the process dictionary for the given document
  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @doc """
  Converts the XML fragment to a preliminary representation.
  This is useful when you need to serialize or transfer the fragment's structure.
  """
  @spec as_prelim(t) :: Yex.XmlFragmentPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = xml_fragment) do
    Doc.run_in_worker_process(doc,
      do:
        children(xml_fragment)
        |> Enum.map(fn child -> Yex.Output.as_prelim(child) end)
        |> Yex.XmlFragmentPrelim.new()
    )
  end

  defimpl Yex.Output do
    @doc """
    Implementation of the Yex.Output protocol for XmlFragment.
    Converts the XML fragment to its preliminary representation.
    """
    def as_prelim(xml_fragment) do
      Yex.XmlFragment.as_prelim(xml_fragment)
    end
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
