defmodule Yex.XmlFragment do
  @moduledoc """
  A shared type to manage a collection of Y.Xml* Nodes

  """

  alias Yex.Xml

  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: reference(),
          reference: reference()
        }

  def first_child(%__MODULE__{} = xml_fragment) do
    get(xml_fragment, 0)
    |> case do
      {:ok, node} -> node
      :error -> nil
    end
  end

  @spec children(t) :: Enumerable.t(Yex.XmlElement.t() | Yex.XmlText.t())
  def children(%__MODULE__{} = xml_fragment) do
    Stream.unfold(first_child(xml_fragment), fn
      nil -> nil
      xml -> {xml, Xml.next_sibling(xml)}
    end)
  end

  def length(%__MODULE__{} = xml_fragment) do
    Yex.Nif.xml_fragment_length(xml_fragment, cur_txn(xml_fragment))
  end

  def insert(%__MODULE__{} = xml_fragment, index, content) do
    Yex.Nif.xml_fragment_insert(xml_fragment, cur_txn(xml_fragment), index, content)
  end

  def delete(%__MODULE__{} = xml_fragment, index, length) do
    Yex.Nif.xml_fragment_delete_range(xml_fragment, cur_txn(xml_fragment), index, length)
    |> Yex.Nif.Util.unwrap_tuple()
  end

  def push(%__MODULE__{} = xml_fragment, content) do
    insert(xml_fragment, __MODULE__.length(xml_fragment), content)
  end

  def unshift(%__MODULE__{} = xml_fragment, content) do
    insert(xml_fragment, 0, content)
  end

  @deprecated "Rename to `fetch/2`"
  @spec get(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def get(%__MODULE__{} = xml_fragment, index) do
    fetch(xml_fragment, index)
  end

  @spec fetch(t, integer()) :: {:ok, Yex.XmlElement.t() | Yex.XmlText.t()} | :error
  def fetch(%__MODULE__{} = xml_fragment, index) do
    Yex.Nif.xml_fragment_get(xml_fragment, cur_txn(xml_fragment), index)
    |> Yex.Nif.Util.unwrap_tuple()
  end

  @spec fetch(t, integer()) :: Yex.XmlElement.t() | Yex.XmlText.t()
  def fetch!(%__MODULE__{} = map, index) do
    case fetch(map, index) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Index out of bounds"
    end
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{} = xml_fragment) do
    Yex.Nif.xml_fragment_to_string(xml_fragment, cur_txn(xml_fragment))
  end

  defp cur_txn(%__MODULE__{doc: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
