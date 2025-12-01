defmodule Yex.WeakTest do
  use ExUnit.Case
  alias Yex.XmlTextPrelim
  alias Yex.WeakLink
  alias Yex.WeakPrelim
  alias Yex.{Doc, Text}
  doctest WeakLink
  doctest WeakPrelim

  setup do
    doc = Doc.new()
    {:ok, %{doc: doc}}
  end

  def exchange_updates(doc1, doc2) do
    sv2 = Yex.encode_state_vector!(doc2)
    state1 = Yex.encode_state_as_update!(doc1, sv2)
    :ok = Yex.apply_update(doc2, state1)

    sv1 = Yex.encode_state_vector!(doc1)
    state2 = Yex.encode_state_as_update!(doc2, sv1)
    :ok = Yex.apply_update(doc1, state2)
  end

  describe "text quote" do
    test "basic_text", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      # "abcd"
      Text.insert(text, 0, "abcd")
      a1 = Yex.Doc.get_array(doc, "array")

      prelim = Text.quote(text, 1, 2)
      assert %WeakPrelim{} = prelim
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)

      assert "bc" = WeakLink.to_string(l1)
    end

    test "quote error", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      # "abcd"
      Text.insert(text, 0, "abcd")

      assert {:error, :out_of_bounds} = Text.quote(text, 1, 0)
    end

    test "test cast", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      # "abcd"
      Text.insert(text, 0, "abcd")
      a1 = Yex.Doc.get_array(doc, "array")

      prelim = Text.quote(text, 1, 2)
      assert %WeakPrelim{} = prelim
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)

      assert "bc" = WeakLink.to_string(l1)
    end
  end

  describe "xml text quote" do
    test "basic_text", %{doc: doc} do
      xml = Doc.get_xml_fragment(doc, "xml")
      xml_text = Yex.XmlFragment.insert_and_get(xml, 0, XmlTextPrelim.from("test"))

      # "abcd"
      Yex.XmlText.insert(xml_text, 0, "abcd")
      a1 = Yex.Doc.get_array(doc, "array")

      prelim = Yex.XmlText.quote(xml_text, 1, 2)
      assert %WeakPrelim{} = prelim
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)

      assert "bc" = WeakLink.to_string(l1)
    end

    test "test cast", %{doc: doc} do
      xml = Doc.get_xml_fragment(doc, "xml")
      xml_text = Yex.XmlFragment.insert_and_get(xml, 0, XmlTextPrelim.from("test"))

      # "abcd"
      Yex.XmlText.insert(xml_text, 0, "abcd")
      a1 = Yex.Doc.get_array(doc, "array")

      prelim = Yex.XmlText.quote(xml_text, 1, 2)
      assert %WeakPrelim{} = prelim
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)

      assert "bc" = WeakLink.to_string(l1)
    end
  end

  describe "array quote" do
    test "self_quotation", %{} do
      d1 = Doc.new()
      a1 = Doc.get_array(d1, "array")
      d2 = Doc.new()
      a2 = Doc.get_array(d2, "array")
      Yex.Array.insert_list(a1, 0, ["1", "2", "3", "4"])
      l1 = Yex.Array.quote(a1, 0, 3)
      #  link is inserted into its own range
      l1 = Yex.Array.insert_and_get(a1, 1, l1)
      assert ["1", l1, "2", "3"] == WeakLink.to_list(l1)
      assert "1" == Yex.Array.fetch!(a1, 0)
      assert l1 == Yex.Array.fetch!(a1, 1)
      assert "2" == Yex.Array.fetch!(a1, 2)
      assert "3" == Yex.Array.fetch!(a1, 3)
      assert "4" == Yex.Array.fetch!(a1, 4)
      exchange_updates(d1, d2)

      l2 = Yex.Array.fetch!(a2, 1)
      assert ["1", l2, "2", "3"] == WeakLink.to_list(l2)
      assert "1" == Yex.Array.fetch!(a2, 0)
      assert l2 == Yex.Array.fetch!(a2, 1)
      assert "2" == Yex.Array.fetch!(a2, 2)
      assert "3" == Yex.Array.fetch!(a2, 3)
      assert "4" == Yex.Array.fetch!(a2, 4)
    end

    test "test cast" do
      d1 = Doc.new()
      a1 = Doc.get_array(d1, "array")
      m1 = Doc.get_map(d1, "map")
      Yex.Array.insert_list(a1, 0, ["1", "2", "3", "4"])
      l1 = Yex.Array.quote(a1, 0, 3)

      l1 = Yex.Map.set_and_get(m1, "key", l1)

      assert ["1", "2", "3"] = WeakLink.to_list(l1)
    end
  end

  describe "map link" do
    test "update" do
      d1 = Doc.new()
      m1 = Doc.get_map(d1, "map")
      d2 = Doc.new()
      m2 = Doc.get_map(d2, "map")

      nested = Yex.MapPrelim.from([{"a1", "hello"}])
      Yex.Map.set(m1, "a", nested)
      link = Yex.Map.link(m1, "a")
      link1 = Yex.Map.set_and_get(m1, "b", link)

      exchange_updates(d1, d2)

      link2 = Yex.Map.fetch!(m2, "b")
      l1 = WeakLink.deref(link1)
      l2 = WeakLink.deref(link2)
      assert Yex.Map.get(l1, "a1") == Yex.Map.get(l2, "a1")
      assert "hello" == Yex.Map.get(l2, "a1")
      Yex.Map.set(l2, "a2", "world")

      exchange_updates(d1, d2)

      l1 = WeakLink.deref(link1)
      l2 = WeakLink.deref(link2)

      assert "world" == Yex.Map.get(l2, "a2")
      assert Yex.Map.get(l1, "a2") == Yex.Map.get(l2, "a2")
    end

    test "as_prelim returns WeakPrelim struct" do
      doc = Doc.new()
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "abcd")
      prelim = Text.quote(text, 1, 2)
      a1 = Yex.Doc.get_array(doc, "array")
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)
      result = WeakLink.as_prelim(l1)
      assert %WeakPrelim{} = result
    end

    test "Yex.Output.as_prelim returns WeakPrelim struct" do
      doc = Doc.new()
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "abcd")
      prelim = Text.quote(text, 1, 2)
      a1 = Yex.Doc.get_array(doc, "array")
      l1 = Yex.Array.insert_and_get(a1, 0, prelim)
      result = Yex.Output.as_prelim(l1)
      assert %WeakPrelim{} = result
    end
  end
end
