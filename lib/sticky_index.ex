defmodule Yex.StickyIndex do
  @moduledoc """
  A shareable Array-like type that supports efficient insert/delete of elements at any position.
  """
  defstruct [
    :reference,
    :assoc
  ]

  @type t :: %__MODULE__{
          reference: reference(),
          assoc: :before | :after
        }

  @type shared_type ::
          %Yex.Array{}
          | %Yex.Text{}
          | %Yex.XmlElement{}
          | %Yex.XmlText{}
          | %Yex.XmlFragment{}
  @spec new(shared_type, integer(), :before | :after) :: t
  def new(shared_type, index, assoc) do
    Yex.Nif.sticky_index_new(shared_type, cur_txn(shared_type), index, assoc)
  end


  @spec get_offset(t) :: {:ok, %{index: integer(), assoc: :before | :after}} | :error
  def get_offset(%__MODULE__{} = sticky_index) do
    Yex.Nif.sticky_index_get_offset(sticky_index, cur_txn(sticky_index))
  end

  defp cur_txn(%{doc: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
