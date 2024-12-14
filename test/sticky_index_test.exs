defmodule Yex.StickyIndexTest do
  use ExUnit.Case
  alias Yex.{StickyIndex, Doc, Text}

  test "new" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    Doc.transaction(doc, fn ->
      Text.insert(txt, 0, "abc")
      #  => 'abc'
      # create position tracker (marked as . in the comments)
      pos = StickyIndex.new(txt, 2, :after)
      # => 'ab.c'

      # modify text
      Text.insert(txt, 1, "def")
      # => 'adefb.c'
      Text.delete(txt, 4, 1)
      # => 'adef.c'

      # get current offset index within the containing collection
      {:ok, a} = StickyIndex.get_offset(pos)
      # => 4
      assert a.index == 4
      assert a.assoc == :after
    end)
  end
end
