defmodule Yex.XmlFragment do
  @moduledoc """
  A shared type to manage a collection of Y.Xml* Nodes

  """

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

  def get(%__MODULE__{} = xml_fragment, index) do
    Yex.Nif.xml_fragment_get(xml_fragment, cur_txn(xml_fragment), index)
    |> Yex.Nif.Util.unwrap_tuple()
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{} = xml_fragment) do
    Yex.Nif.xml_fragment_to_string(xml_fragment, cur_txn(xml_fragment))
  end

  defp cur_txn(%__MODULE__{doc: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
