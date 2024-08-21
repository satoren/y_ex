defmodule YexXmlElementTest do
  use ExUnit.Case
  alias Yex.{Doc, XmlFragment, XmlElement, XmlElementPrelim, XmlText, XmlTextPrelim, Xml}
  doctest XmlElement
  doctest XmlElementPrelim

  describe "xml_element" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, xml} = XmlFragment.get(f, 0)
      %{doc: d1, xml_element: xml, xml_fragment: f}
    end

    test "insert_attribute", %{doc: d1, xml_element: xml1} do
      XmlElement.insert_attribute(xml1, "height", "10")

      assert "10" == XmlElement.get_attribute(xml1, "height")

      d2 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d2, "xml")

      XmlFragment.push(f, XmlElementPrelim.empty("div"))

      {:ok, xml2} = XmlFragment.get(f, 0)

      {:ok, u} = Yex.encode_state_as_update(d1)
      Yex.apply_update(d2, u)

      assert "10" == XmlElement.get_attribute(xml2, "height")
    end

    test "unshift", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlElement.get(xml, 0)
      XmlElement.unshift(xml, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlElement.get(xml, 0)
    end

    test "delete", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from("content"))
      assert "<div>content</div>" == XmlElement.to_string(xml)
      assert :ok == XmlElement.delete(xml, 0, 1)
      assert "<div></div>" == XmlElement.to_string(xml)
    end

    test "get_attributes", %{xml_element: xml1} do
      XmlElement.insert_attribute(xml1, "height", "10")
      XmlElement.insert_attribute(xml1, "width", "12")

      assert %{"height" => "10", "width" => "12"} == XmlElement.get_attributes(xml1)
    end

    test "remove_attribute", %{xml_element: xml1} do
      XmlElement.insert_attribute(xml1, "height", "10")
      XmlElement.insert_attribute(xml1, "width", "12")
      XmlElement.remove_attribute(xml1, "height")
      assert %{"width" => "12"} == XmlElement.get_attributes(xml1)
    end

    test "first_child", %{xml_element: e} do
      assert nil == XmlElement.first_child(e)
      XmlElement.push(e, XmlTextPrelim.from(""))
      assert %XmlText{} = XmlElement.first_child(e)
    end

    test "next_sibling", %{xml_element: xml_element, xml_fragment: xml_fragment} do
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_next_content"))
      next = Xml.next_sibling(xml_element)
      next_next = Xml.next_sibling(next)

      assert "next_content" == Xml.to_string(next)
      assert "next_next_content" == Xml.to_string(next_next)
    end

    test "prev_sibling", %{xml_element: xml_element, xml_fragment: xml_fragment} do
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlElementPrelim.empty("div"))
      next = Xml.next_sibling(xml_element)
      next = Xml.next_sibling(next)
      assert "<div></div>" == Xml.to_string(next)
      next_prev = Xml.prev_sibling(next)

      assert "next_content" == Xml.to_string(next_prev)
    end
  end
end
