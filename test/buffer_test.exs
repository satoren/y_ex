defmodule Yex.BufferTest do
  use ExUnit.Case, async: true

  alias Yex.{
    Array,
    ArrayPrelim,
    Buffer,
    Doc,
    Map,
    MapPrelim,
    Text,
    XmlElementPrelim,
    XmlFragment
  }

  doctest Buffer

  setup do
    doc = Doc.new()
    {:ok, doc: doc, map: Doc.get_map(doc, "map"), array: Doc.get_array(doc, "array")}
  end

  describe "a bare binary" do
    test "that is valid UTF-8 is stored as a string", %{map: map} do
      assert :ok = Map.set(map, "key", "RIFF")
      assert {:ok, "RIFF"} = Map.fetch(map, "key")
    end

    test "that is not valid UTF-8 is stored as a buffer", %{map: map} do
      assert :ok = Map.set(map, "key", <<0xFF, 0xD8, 0x00, 0x80>>)
      assert {:ok, %Buffer{data: <<0xFF, 0xD8, 0x00, 0x80>>}} = Map.fetch(map, "key")
    end
  end

  describe "Yex.Buffer" do
    test "stores bytes as a buffer whatever they contain", %{map: map} do
      samples = %{
        "binary" => <<0xFF, 0xD8, 0xFF, 0x00, 0x80, 0xC0>>,
        "utf8" => "RIFF plain text that is valid UTF-8",
        "empty" => <<>>,
        "one" => <<0>>,
        "large" => :crypto.strong_rand_bytes(300_000)
      }

      for {key, sample} <- samples, do: assert(:ok = Map.set(map, key, Buffer.from(sample)))

      for {key, sample} <- samples do
        assert {:ok, %Buffer{data: sample}} == Map.fetch(map, key)
      end
    end

    test "keeps its type when read and written again", %{doc: doc, map: map} do
      :ok = Map.set(map, "key", Buffer.from("RIFF"))
      {:ok, update} = Yex.encode_state_as_update(doc)

      other = Doc.new()
      :ok = Yex.apply_update(other, update)
      other_map = Doc.get_map(other, "map")
      assert {:ok, %Buffer{data: "RIFF"} = value} = Map.fetch(other_map, "key")

      assert :ok = Map.set(other_map, "copy", value)
      assert {:ok, ^value} = Map.fetch(other_map, "copy")
      assert %{"key" => ^value, "copy" => ^value} = Map.to_json(other_map)
    end

    test "is accepted in an array, a prelim and an XML attribute", %{
      doc: doc,
      map: map,
      array: array
    } do
      riff = Buffer.from("RIFF")

      assert :ok = Array.insert(array, 0, riff)
      assert {:ok, ^riff} = Array.fetch(array, 0)

      assert :ok = Map.set(map, "nested", MapPrelim.from(%{"data" => riff}))
      {:ok, nested} = Map.fetch(map, "nested")
      assert {:ok, ^riff} = Map.fetch(nested, "data")

      assert :ok = Map.set(map, "list", ArrayPrelim.from([Buffer.from(<<1, 2>>), "text"]))
      {:ok, list} = Map.fetch(map, "list")
      assert [%Buffer{data: <<1, 2>>}, "text"] = Array.to_list(list)

      fragment = Doc.get_xml_fragment(doc, "xml")
      :ok = XmlFragment.push(fragment, XmlElementPrelim.new("img", [], %{"bytes" => riff}))
      {:ok, element} = XmlFragment.fetch(fragment, 0)
      assert ^riff = Yex.XmlElement.get_attribute(element, "bytes")
    end

    test "in a text's formatting attributes or an embed reads as a list after a sync",
         %{doc: doc} do
      text = Doc.get_text(doc, "text")

      :ok = Text.insert(text, 0, "hi", %{"bold" => true, "blob" => Buffer.from("RIFF")})
      :ok = Text.insert_embed(text, 2, Buffer.from("EMB"))

      {:ok, update} = Yex.encode_state_as_update(doc)
      other = Doc.new()
      :ok = Yex.apply_update(other, update)

      assert [
               %{insert: "hi", attributes: %{"bold" => true, "blob" => [82.0, 73.0, 70.0, 70.0]}},
               %{insert: [69.0, 77.0, 66.0]}
             ] = Text.to_delta(Doc.get_text(other, "text"))
    end

    test "refuses data that is not a binary", %{map: map} do
      assert_raise ErlangError, fn -> Map.set(map, "key", %Buffer{data: [1, 2]}) end
      assert_raise ErlangError, fn -> Map.set(map, "key", %Buffer{data: nil}) end
    end

    test "is the only struct a value accepts", %{map: map} do
      assert_raise ErlangError, fn -> Map.set(map, "key", 1..2) end
    end
  end
end
