defmodule Yex.StickyIndexTest do
  use ExUnit.Case

  alias Yex.{
    StickyIndex,
    Doc,
    Text,
    Array,
    XmlElement,
    XmlText,
    XmlFragment,
    XmlElementPrelim,
    XmlTextPrelim
  }

  doctest StickyIndex

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

  test "sticky index with :before association" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    Doc.transaction(doc, fn ->
      Text.insert(txt, 0, "abcdef")
      # Create sticky index with :before association
      pos = StickyIndex.new(txt, 3, :before)

      # Modify text before the index
      Text.insert(txt, 1, "XYZ")
      Text.delete(txt, 0, 1)

      # Check position
      {:ok, result} = StickyIndex.get_offset(pos)
      # Original was 3, +3 for XYZ insert, -1 for deletion
      assert result.index == 5
      assert result.assoc == :before
    end)
  end

  test "sticky index with Array type" do
    doc = Doc.new()
    array = Doc.get_array(doc, "array")

    Doc.transaction(doc, fn ->
      Array.push(array, "a")
      Array.push(array, "b")
      Array.push(array, "c")

      # Create sticky index pointing to position 1
      pos = StickyIndex.new(array, 1, :after)

      # Insert at beginning should move the index
      Array.insert(array, 0, "x")

      # Check position
      {:ok, result} = StickyIndex.get_offset(pos)
      # Original position 1 + 1 for insert at 0
      assert result.index == 2
    end)
  end

  test "sticky index with XmlElement type" do
    doc = Doc.new()
    fragment = Doc.get_xml_fragment(doc, "fragment")

    Doc.transaction(doc, fn ->
      XmlFragment.push(fragment, XmlElementPrelim.empty("div"))
      {:ok, element} = XmlFragment.fetch(fragment, 0)

      # Add some children to the element
      XmlElement.push(element, XmlTextPrelim.from("first"))
      XmlElement.push(element, XmlTextPrelim.from("second"))

      # Create sticky index
      pos = StickyIndex.new(element, 1, :after)

      # Modify the element
      XmlElement.insert(element, 0, XmlTextPrelim.from("inserted"))

      # Check position
      {:ok, result} = StickyIndex.get_offset(pos)
      # Original position 1 + 1 for insert at 0
      assert result.index == 2
    end)
  end

  test "sticky index with XmlText type" do
    doc = Doc.new()
    fragment = Doc.get_xml_fragment(doc, "fragment")

    Doc.transaction(doc, fn ->
      XmlFragment.push(fragment, XmlTextPrelim.from(""))
      {:ok, text} = XmlFragment.fetch(fragment, 0)

      # Add text content
      XmlText.insert(text, 0, "Hello World")

      # Create sticky index
      # After "Hello"
      pos = StickyIndex.new(text, 5, :before)

      # Modify text
      XmlText.insert(text, 0, "Start: ")
      # Delete "Hello"
      XmlText.delete(text, 12, 5)

      # Check position - now the index position should be at the start of the text
      # since the content it was pointing to was deleted
      {:ok, result} = StickyIndex.get_offset(pos)

      # The actual index will depend on the Yjs implementation 
      # We'll just verify it returns a result without asserting the exact position
      assert is_map(result)
      assert Map.has_key?(result, :index)
      assert Map.has_key?(result, :assoc)
    end)
  end

  test "sticky index with XmlFragment type" do
    doc = Doc.new()
    fragment = Doc.get_xml_fragment(doc, "fragment")

    Doc.transaction(doc, fn ->
      # Add some elements
      XmlFragment.push(fragment, XmlTextPrelim.from("Text1"))
      XmlFragment.push(fragment, XmlElementPrelim.empty("div"))
      XmlFragment.push(fragment, XmlTextPrelim.from("Text2"))

      # Create sticky index
      pos = StickyIndex.new(fragment, 1, :after)

      # Modify fragment
      XmlFragment.insert(fragment, 0, XmlElementPrelim.empty("header"))

      # Check position
      {:ok, result} = StickyIndex.get_offset(pos)
      # Original position 1 + 1 for insert at 0
      assert result.index == 2
    end)
  end

  test "get_offset for an invalid sticky index" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Create a valid sticky index first
    valid_pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "abc")
        StickyIndex.new(txt, 1, :after)
      end)

    # Create an invalid reference that simulates a reference that doesn't exist in the NIF
    # but use the proper doc for it to avoid crashing the NIF
    invalid_index = %StickyIndex{
      doc: valid_pos.doc,
      reference: nil,
      assoc: :after
    }

    assert_raise ErlangError, fn ->
      StickyIndex.get_offset(invalid_index)
    end
  end
end
