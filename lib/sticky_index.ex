defmodule Yex.StickyIndex do
  @moduledoc """
  A sticky index provides position references that are unaffected by document changes, based on the Yjs model.
  It maintains its relative position when placed before or after specific characters or elements.

  ## Features
  - Stable position references unaffected by document changes
  - Compatible with shared types like Text, Array, and XML
  - Maintains relative positions after insert/delete operations
  - Ideal for tracking cursor positions and text selections

  ## Usage
  Numeric indices are unsuitable for tracking user selections because their positions
  change when content is inserted or deleted. Sticky indices provide stable references
  that maintain their relative positions through such changes:

      iex> alias Yex.{StickyIndex, Doc, Text}
      iex> doc = Doc.new()
      iex> txt = Doc.get_text(doc, "text")
      iex> Doc.transaction(doc, fn ->
      ...>  Text.insert(txt, 0, "abc")
      ...>  # => 'abc'
      ...>  # Create position tracker (marked as . in comments)
      ...>  pos = StickyIndex.new(txt, 2, :after)
      ...>  # => 'ab.c'
      ...>
      ...>  # Modify text
      ...>  Text.insert(txt, 1, "def")
      ...>  # => 'adefb.c'
      ...>  Text.delete(txt, 4, 1)
      ...>  # => 'adef.c'
      ...>
      ...>  # Get current offset index
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
          doc: Yex.Doc.t(),
          reference: reference(),
          assoc: :before | :after
        }

  alias Yex.Doc
  require Yex.Doc

  @type shared_type ::
          %Yex.Array{}
          | %Yex.Text{}
          | %Yex.XmlElement{}
          | %Yex.XmlText{}
          | %Yex.XmlFragment{}
  @spec new(shared_type, integer(), :before | :after) :: t
  def new(%{doc: doc} = shared_type, index, assoc) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.sticky_index_new(shared_type, cur_txn(shared_type), index, assoc)
    )
  end

  @spec get_offset(t) :: {:ok, %{index: integer(), assoc: :before | :after}} | :error
  def get_offset(%__MODULE__{doc: doc} = sticky_index) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.sticky_index_get_offset(sticky_index, cur_txn(sticky_index))
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end
end
