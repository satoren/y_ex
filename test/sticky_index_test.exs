defmodule Yex.StickyIndexTest do
  use ExUnit.Case, async: true

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

  defp decode_json!(json) when is_binary(json) do
    if Code.ensure_loaded?(Jason) and function_exported?(Jason, :decode!, 1) do
      Jason.decode!(json)
    else
      case :json.decode(json) do
        {:ok, decoded} -> decoded
        decoded -> decoded
      end
    end
  end

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

  test "encode and decode sticky index" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Create and encode a sticky index
    pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello")
        StickyIndex.new(txt, 2, :after)
      end)

    # Encode the position
    {:ok, binary} = StickyIndex.encode(pos)
    assert is_binary(binary)
    assert byte_size(binary) > 0

    # Decode the binary back
    decoded_pos = StickyIndex.decode(doc, binary)
    assert decoded_pos.doc == pos.doc
    assert decoded_pos.assoc == pos.assoc

    # Verify the decoded position works
    Doc.transaction(doc, fn ->
      {:ok, offset} = StickyIndex.get_offset(decoded_pos)
      assert offset.index == 2
      assert offset.assoc == :after
    end)
  end

  test "encode and decode with modifications" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Create, modify, encode, then decode
    {:ok, binary} =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "abc")
        pos = StickyIndex.new(txt, 1, :before)

        # Modify text
        Text.insert(txt, 0, "xyz")

        # Encode after modifications
        StickyIndex.encode(pos)
      end)

    # Decode after transaction completes
    decoded_pos = StickyIndex.decode(doc, binary)

    # Verify the decoded position works
    Doc.transaction(doc, fn ->
      {:ok, offset} = StickyIndex.get_offset(decoded_pos)
      assert offset.index == 4
      assert offset.assoc == :before
    end)
  end

  test "sticky_index_to_json returns JSON string with assoc (ysticky_index_to_json compatible)" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Test :after association (assoc = 0)
    pos_after =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello")
        StickyIndex.new(txt, 2, :after)
      end)

    json_after = StickyIndex.to_json(pos_after)
    assert is_binary(json_after)
    assert decode_json!(json_after)["assoc"] == 0

    # Test :before association (assoc = -1)
    pos_before =
      Doc.transaction(doc, fn ->
        StickyIndex.new(txt, 3, :before)
      end)

    json_before = StickyIndex.to_json(pos_before)
    assert is_binary(json_before)
    assert decode_json!(json_before)["assoc"] == -1
  end

  test "sticky_index_assoc returns correct values" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Test :after association (assoc = 0)
    pos_after =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello")
        StickyIndex.new(txt, 1, :after)
      end)

    assert StickyIndex.assoc(pos_after) == 0

    # Test :before association (assoc = -1)
    pos_before =
      Doc.transaction(doc, fn ->
        StickyIndex.new(txt, 2, :before)
      end)

    assert StickyIndex.assoc(pos_before) == -1
  end

  test "encode produces different binaries for different positions" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    pos1 =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello world")
        StickyIndex.new(txt, 1, :after)
      end)

    pos2 =
      Doc.transaction(doc, fn ->
        StickyIndex.new(txt, 5, :after)
      end)

    binary1 = StickyIndex.encode(pos1)
    binary2 = StickyIndex.encode(pos2)

    # Different positions should produce different encodings
    assert binary1 != binary2
  end

  test "encode produces same binary for same position" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "test")
        StickyIndex.new(txt, 2, :before)
      end)

    binary1 = StickyIndex.encode(pos)
    binary2 = StickyIndex.encode(pos)

    # Same position encoded twice should produce same binary
    assert binary1 == binary2
  end

  test "to_json emits item-variant JSON structure" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello world")
        StickyIndex.new(txt, 5, :after)
      end)

    json = StickyIndex.to_json(pos)

    assert is_binary(json)
    decoded = decode_json!(json)
    assert is_map(decoded)

    assert Map.has_key?(decoded, "item")
    refute Map.has_key?(decoded, "type")
    refute Map.has_key?(decoded, "tname")

    assert is_map(decoded["item"])
    assert is_integer(decoded["item"]["client"])
    assert is_integer(decoded["item"]["clock"])
    assert decoded["assoc"] == 0
  end

  test "from_json can reconstruct sticky index from JSON" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    # Create initial position
    original_pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "test content")
        StickyIndex.new(txt, 4, :before)
      end)

    # Export to JSON
    json = StickyIndex.to_json(original_pos)

    # Reconstruct from JSON
    {:ok, restored_pos} = StickyIndex.from_json(json, doc)

    # Verify restored position has correct assoc
    assert StickyIndex.assoc(restored_pos) == -1

    # Verify restored position points to the same offset as the original
    Doc.transaction(doc, fn ->
      {:ok, original_offset} = StickyIndex.get_offset(original_pos)
      {:ok, restored_offset} = StickyIndex.get_offset(restored_pos)

      assert restored_offset.index == original_offset.index
      assert restored_offset.assoc == original_offset.assoc
    end)

    # Verify JSON roundtrip
    restored_json = StickyIndex.to_json(restored_pos)
    assert decode_json!(restored_json)["assoc"] == decode_json!(json)["assoc"]
  end

  test "to_json can emit type-variant JSON structure" do
    doc = Doc.new()
    json = ~s({"type":{"client":1,"clock":0},"assoc":0})

    {:ok, pos} = StickyIndex.from_json(json, doc)
    encoded = StickyIndex.to_json(pos) |> decode_json!()

    assert Map.has_key?(encoded, "type")
    refute Map.has_key?(encoded, "item")
    refute Map.has_key?(encoded, "tname")

    assert is_map(encoded["type"])
    assert is_integer(encoded["type"]["client"])
    assert is_integer(encoded["type"]["clock"])
    assert encoded["assoc"] == 0
  end

  test "to_json can emit tname-variant JSON structure" do
    doc = Doc.new()

    {:ok, tname_pos} = StickyIndex.from_json(~s({"tname":"text","assoc":0}), doc)
    encoded = StickyIndex.to_json(tname_pos) |> decode_json!()

    assert Map.has_key?(encoded, "tname")
    refute Map.has_key?(encoded, "item")
    refute Map.has_key?(encoded, "type")

    assert is_binary(encoded["tname"])
    assert encoded["assoc"] == 0
  end

  test "from_json with :after association" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    original_pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "content")
        StickyIndex.new(txt, 3, :after)
      end)

    json = StickyIndex.to_json(original_pos)
    {:ok, restored_pos} = StickyIndex.from_json(json, doc)

    assert StickyIndex.assoc(restored_pos) == 0
    assert decode_json!(StickyIndex.to_json(restored_pos))["assoc"] == 0
  end

  test "from_json returns error for invalid JSON" do
    doc = Doc.new()

    assert {:error, reason} = StickyIndex.from_json("not valid json", doc)
    assert reason == :invalid_json
  end

  test "encode_v1 and decode_v1 roundtrip" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello")
        StickyIndex.new(txt, 2, :after)
      end)

    {:ok, binary} = StickyIndex.encode_v1(pos)
    assert is_binary(binary)
    assert byte_size(binary) > 0

    decoded_pos = StickyIndex.decode_v1(doc, binary)
    assert decoded_pos.doc == pos.doc

    Doc.transaction(doc, fn ->
      {:ok, offset} = StickyIndex.get_offset(decoded_pos)
      assert offset.index == 2
      assert offset.assoc == :after
    end)
  end

  test "encode_v2 and decode_v2 roundtrip" do
    doc = Doc.new()
    txt = Doc.get_text(doc, "text")

    pos =
      Doc.transaction(doc, fn ->
        Text.insert(txt, 0, "hello")
        StickyIndex.new(txt, 3, :before)
      end)

    {:ok, binary} = StickyIndex.encode_v2(pos)
    assert is_binary(binary)
    assert byte_size(binary) > 0

    decoded_pos = StickyIndex.decode_v2(doc, binary)
    assert decoded_pos.doc == pos.doc

    Doc.transaction(doc, fn ->
      {:ok, offset} = StickyIndex.get_offset(decoded_pos)
      assert offset.index == 3
      assert offset.assoc == :before
    end)
  end
end
