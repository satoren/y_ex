defmodule Yex.XmlElement do
  @moduledoc """
  A shared type that represents an XML node

  """

  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: reference(),
          reference: reference()
        }

  def first_child(%__MODULE__{} = xml_element) do
    get(xml_element, 0)
    |> case do
      {:ok, node} -> node
      :error -> nil
    end
  end

  def length(%__MODULE__{} = xml_element) do
    Yex.Nif.xml_element_length(xml_element, cur_txn(xml_element))
  end

  def insert(%__MODULE__{} = xml_element, index, content) do
    Yex.Nif.xml_element_insert(xml_element, cur_txn(xml_element), index, content)
  end

  def delete(%__MODULE__{} = xml_element, index, length) do
    Yex.Nif.xml_element_delete_range(xml_element, cur_txn(xml_element), index, length)
    |> Yex.Nif.Util.unwrap_tuple()
  end

  def push(%__MODULE__{} = xml_element, content) do
    insert(xml_element, __MODULE__.length(xml_element), content)
  end

  def unshift(%__MODULE__{} = xml_element, content) do
    insert(xml_element, 0, content)
  end

  def get(%__MODULE__{} = xml_element, index) do
    Yex.Nif.xml_element_get(xml_element, cur_txn(xml_element), index)
    |> Yex.Nif.Util.unwrap_tuple()
  end

  def insert_attribute(%__MODULE__{} = xml_element, key, value) do
    Yex.Nif.xml_element_insert_attribute(xml_element, cur_txn(xml_element), key, value)
  end

  def remove_attribute(%__MODULE__{} = xml_element, key) do
    Yex.Nif.xml_element_remove_attribute(xml_element, cur_txn(xml_element), key)
  end

  def get_attribute(%__MODULE__{} = xml_element, key) do
    Yex.Nif.xml_element_get_attribute(xml_element, cur_txn(xml_element), key)
  end

  def get_attributes(%__MODULE__{} = xml_element) do
    Yex.Nif.xml_element_get_attributes(xml_element, cur_txn(xml_element))
  end

  def next_sibling(%__MODULE__{} = xml_element) do
    Yex.Nif.xml_element_next_sibling(xml_element, cur_txn(xml_element))
  end

  def prev_sibling(%__MODULE__{} = xml_element) do
    Yex.Nif.xml_element_prev_sibling(xml_element, cur_txn(xml_element))
  end

  def to_string(%__MODULE__{} = xml_element) do
    Yex.Nif.xml_element_to_string(xml_element, cur_txn(xml_element))
  end

  defp cur_txn(%__MODULE__{doc: doc_ref}) do
    Process.get(doc_ref, nil)
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
          attributes: %{String.t() => String.t()},
          children: [Yex.XmlElementPrelim.t() | Yex.XmlTextPrelim.t()]
        }

  def new(tag, children) do
    %__MODULE__{
      tag: tag,
      attributes: %{},
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
