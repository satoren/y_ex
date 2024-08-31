defmodule YexXmlFragmentTest do
  use ExUnit.Case
  alias Yex.{Doc, XmlFragment, XmlElement, XmlElementPrelim, XmlText, XmlTextPrelim}
  doctest XmlFragment

  setup do
    doc = Doc.with_options(%Doc.Options{client_id: 1})
    f = Doc.get_xml_fragment(doc, "xml")
    %{doc: doc, xml_fragment: f}
  end

  describe "xml_fragment" do
    test "push", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlFragment.fetch(f, 0)
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlFragment.fetch(f, 1)
    end

    test "unshift", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlFragment.fetch(f, 0)
      XmlFragment.unshift(f, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlFragment.fetch(f, 0)
    end

    test "fetch", %{xml_fragment: xml} do
      XmlFragment.push(xml, XmlElementPrelim.empty("div"))

      assert {:ok, %XmlElement{}} = XmlFragment.fetch(xml, 0)
      assert :error == XmlFragment.fetch(xml, 1)
    end

    test "fetch!", %{xml_fragment: xml} do
      XmlFragment.push(xml, XmlElementPrelim.empty("div"))

      assert %XmlElement{} = XmlFragment.fetch!(xml, 0)

      assert_raise ArgumentError, "Index out of bounds", fn ->
        XmlFragment.fetch!(xml, 1)
      end
    end

    test "delete", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from(""))
      :ok = XmlFragment.delete(f, 0, 1)
      :error = XmlFragment.fetch(f, 0)
    end

    test "first_child", %{xml_fragment: f} do
      assert nil == XmlFragment.first_child(f)
      XmlFragment.push(f, XmlTextPrelim.from(""))
      assert %XmlText{} = XmlFragment.first_child(f)
    end

    test "to_string", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      assert "test<div></div>" = XmlFragment.to_string(f)
    end

    test "next_sibling", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))

      stream =
        Stream.unfold(XmlFragment.first_child(f), fn
          nil -> nil
          xml -> {xml, Yex.Xml.next_sibling(xml)}
        end)

      assert 6 === stream |> Enum.to_list() |> Enum.count()
    end

    test "prev_sibling", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))

      stream =
        Stream.unfold(XmlFragment.fetch!(f, 5), fn
          nil -> nil
          xml -> {xml, Yex.Xml.prev_sibling(xml)}
        end)

      assert 6 === stream |> Enum.to_list() |> Enum.count()
    end

    test "children", %{xml_fragment: f} do
      assert 0 === XmlFragment.children(f) |> Enum.count()
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlTextPrelim.from("test"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))

      assert 6 === XmlFragment.children(f) |> Enum.count()
    end
  end
end
