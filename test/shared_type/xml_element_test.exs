defmodule YexXmlElementTest do
  use ExUnit.Case

  alias Yex.{
    Doc,
    XmlFragment,
    XmlElement,
    XmlElementPrelim,
    XmlText,
    XmlTextPrelim,
    Xml,
    SharedType
  }

  doctest XmlElement
  doctest XmlElementPrelim

  describe "xml_element" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_element: xml, xml_fragment: f}
    end

    test "compare", %{doc: doc} do
      xml1 = Doc.get_xml_fragment(doc, "xml")
      xml2 = Doc.get_xml_fragment(doc, "xml")

      assert xml1 == xml2
      xml3 = Doc.get_xml_fragment(doc, "xml3")
      assert xml1 != xml3
    end

    test "fetch", %{xml_element: xml} do
      XmlElement.push(xml, XmlElementPrelim.empty("div"))

      assert {:ok, %XmlElement{}} = XmlElement.fetch(xml, 0)
      assert :error == XmlElement.fetch(xml, 1)
    end

    test "fetch!", %{xml_element: xml} do
      XmlElement.push(xml, XmlElementPrelim.empty("div"))

      assert %XmlElement{} = XmlElement.fetch!(xml, 0)

      assert_raise ArgumentError, "Index out of bounds", fn ->
        XmlElement.fetch!(xml, 1)
      end
    end

    test "insert_attribute", %{doc: d1, xml_element: xml1} do
      XmlElement.insert_attribute(xml1, "height", "10")

      assert "10" == XmlElement.get_attribute(xml1, "height")

      d2 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d2, "xml")

      XmlFragment.push(f, XmlElementPrelim.empty("div"))

      {:ok, xml2} = XmlFragment.fetch(f, 0)

      {:ok, u} = Yex.encode_state_as_update(d1)
      Yex.apply_update(d2, u)

      assert "10" == XmlElement.get_attribute(xml2, "height")
    end

    test "unshift", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlElement.fetch(xml, 0)
      XmlElement.unshift(xml, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlElement.fetch(xml, 0)
    end

    test "insert_after", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from("1"))
      XmlElement.push(xml, XmlTextPrelim.from("2"))
      XmlElement.push(xml, XmlTextPrelim.from("3"))
      assert text2 = XmlElement.fetch!(xml, 1)
      XmlElement.insert_after(xml, text2, XmlElementPrelim.empty("div"))
      assert "<div>12<div></div>3</div>" = XmlElement.to_string(xml)
      XmlElement.insert_after(xml, nil, XmlElementPrelim.empty("div"))
      assert "<div><div></div>12<div></div>3</div>" = XmlElement.to_string(xml)
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

    test "parent", %{xml_element: e, xml_fragment: xml_fragment} do
      parent = Yex.Xml.parent(e)

      assert parent == xml_fragment
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

    test "children", %{xml_element: e} do
      assert 0 === XmlElement.children(e) |> Enum.count()
      XmlElement.push(e, XmlTextPrelim.from("test"))
      XmlElement.push(e, XmlTextPrelim.from("test"))
      XmlElement.push(e, XmlTextPrelim.from("test"))
      XmlElement.push(e, XmlElementPrelim.empty("div"))
      XmlElement.push(e, XmlElementPrelim.empty("div"))
      XmlElement.push(e, XmlElementPrelim.empty("div"))

      assert 6 === XmlElement.children(e) |> Enum.count()
    end

    test "observe", %{doc: doc, xml_element: xml_element} do
      ref = SharedType.observe(xml_element)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlElement.insert_attribute(xml_element, "Hello", "World")
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlEvent{
                        target: ^xml_element,
                        keys: %{"Hello" => %{action: :add, new_value: "World"}},
                        delta: []
                      }, "origin_value", nil}
    end

    test "observe delete ", %{doc: doc, xml_element: xml_element} do
      XmlElement.push(xml_element, XmlTextPrelim.from("Hello"))
      XmlElement.push(xml_element, XmlTextPrelim.from("World"))

      ref = SharedType.observe(xml_element)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlElement.delete(xml_element, 0, 1)
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlEvent{
                        target: ^xml_element,
                        keys: %{},
                        delta: [%{delete: 1}],
                        path: []
                      }, "origin_value", nil}
    end

    test "observe_deep", %{doc: doc, xml_element: xml_element} do
      XmlElement.push(
        xml_element,
        XmlElementPrelim.new("span", [
          XmlElementPrelim.new("span", [
            XmlTextPrelim.from("text")
          ])
        ])
      )

      el2 = XmlElement.first_child(xml_element)
      el3 = XmlElement.first_child(el2)
      text = XmlElement.first_child(el3)

      ref = SharedType.observe_deep(xml_element)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlElement.push(xml_element, XmlTextPrelim.from("1"))
          XmlElement.insert_attribute(el2, "attr", "value")
          XmlElement.push(el3, XmlElementPrelim.empty("div"))
          XmlText.insert(text, 0, "text")
        end)

      assert_receive {:observe_deep_event, ^ref,
                      [
                        %Yex.XmlEvent{
                          path: [],
                          target: ^xml_element,
                          keys: %{},
                          delta: [%{retain: 1}, %{insert: [%Yex.XmlText{}]}]
                        },
                        %Yex.XmlEvent{
                          path: [0],
                          target: ^el2,
                          keys: %{"attr" => %{action: :add, new_value: "value"}},
                          delta: []
                        },
                        %Yex.XmlEvent{
                          keys: %{},
                          path: [0, 0],
                          target: ^el3,
                          delta: [%{retain: 1}, %{insert: [%Yex.XmlElement{}]}]
                        },
                        %Yex.XmlTextEvent{
                          path: [0, 0, 0],
                          target: ^text,
                          delta: [%{insert: "text"}]
                        }
                      ], "origin_value", _metadata}
    end
  end

  describe "XmlElementPrelim" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      %{doc: d1, xml_fragment: f}
    end

    test "XmlElementPrelim.new", %{xml_fragment: xml_fragment} do
      XmlFragment.push(
        xml_fragment,
        XmlElementPrelim.new("div", [
          XmlElementPrelim.empty("div"),
          XmlElementPrelim.empty("div"),
          XmlElementPrelim.new("span", [
            XmlTextPrelim.from("text")
          ]),
          XmlElementPrelim.empty("div"),
          XmlTextPrelim.from("text"),
          XmlTextPrelim.from("div")
        ])
      )

      assert "<div><div></div><div></div><span>text</span><div></div>textdiv</div>" ==
               XmlFragment.to_string(xml_fragment)
    end

    test "XmlElementPrelim.new with attribute", %{xml_fragment: xml_fragment} do
      XmlFragment.push(
        xml_fragment,
        XmlElementPrelim.new(
          "div",
          [
            XmlTextPrelim.from("text")
          ],
          %{"href" => "http://example.com"}
        )
      )

      assert "<div href=\"http://example.com\">text</div>" ==
               XmlFragment.to_string(xml_fragment)
    end
  end
end
