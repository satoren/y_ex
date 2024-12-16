defmodule Yex.StickyIndex do
  @moduledoc """
  A sticky index is based on the Yjs model and is not affected by document changes. E.g. If you place a sticky index before a certain character, it will always point to this character. If you place a sticky index at the end of a type, it will always point to the end of the type.
  A numeric position is often unsuited for user selections, because it does not change when content is inserted before or after.

    `Insert(0, 'x')('a.bc') = 'xa.bc' Where . is the relative position.`

  ## Examples
    iex> alias Yex.{StickyIndex, Doc, Text}
    iex> doc = Doc.new()
    iex> txt = Doc.get_text(doc, "text")
    iex> Doc.transaction(doc, fn ->
    ...>  Text.insert(txt, 0, "abc")
    ...>  #  => 'abc'
    ...>  # create position tracker (marked as . in the comments)
    ...>  pos = StickyIndex.new(txt, 2, :after)
    ...>  # => 'ab.c'
    ...>
    ...>  # modify text
    ...>  Text.insert(txt, 1, "def")
    ...>  # => 'adefb.c'
    ...>  Text.delete(txt, 4, 1)
    ...>  # => 'adef.c'
    ...>
    ...>  # get current offset index within the containing collection
    ...>  {:ok, a} = StickyIndex.get_offset(pos)
    ...>  # => 4
    ...>  assert a.index == 4
    ...> end)
  """
  defstruct [
    :doc,
    :reference,
    :assoc
  ]

  @type t :: %__MODULE__{
          doc: reference(),
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
