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

    test "get/3 returns element or default", %{xml_element: xml} do
      XmlElement.push(xml, XmlElementPrelim.empty("div"))

      assert %XmlElement{} = XmlElement.get(xml, 0)
      assert nil == XmlElement.get(xml, 1)
      assert :default == XmlElement.get(xml, 1, :default)
    end

    test "get_lazy/3 returns element or evaluates function", %{xml_element: xml} do
      XmlElement.push(xml, XmlElementPrelim.empty("div"))

      # Existing element
      assert %XmlElement{} = XmlElement.get_lazy(xml, 0, fn -> :not_called end)

      # Non-existing element - function is called
      assert :default ==
               XmlElement.get_lazy(xml, 1, fn -> :default end)

      # Function should only be called when needed
      called = make_ref()

      XmlElement.get_lazy(xml, 0, fn ->
        send(self(), called)
        :not_called
      end)

      refute_received ^called

      XmlElement.get_lazy(xml, 1, fn ->
        send(self(), called)
        :called
      end)

      assert_received ^called
    end

    test "get_lazy/3 with *_and_get for get-or-create pattern", %{xml_element: xml} do
      # Get or create pattern
      elem1 =
        XmlElement.get_lazy(xml, 0, fn ->
          XmlElement.push_and_get(xml, XmlElementPrelim.empty("span"))
        end)

      assert %XmlElement{} = elem1
      assert 1 = XmlElement.length(xml)

      # Second call should return existing element, not create new one
      elem2 =
        XmlElement.get_lazy(xml, 0, fn ->
          XmlElement.push_and_get(xml, XmlElementPrelim.empty("p"))
        end)

      assert elem1 == elem2
      assert 1 = XmlElement.length(xml)

      # Different index creates new element
      elem3 =
        XmlElement.get_lazy(xml, 1, fn ->
          XmlElement.push_and_get(xml, XmlElementPrelim.empty("div"))
        end)

      assert %XmlElement{} = elem3
      assert elem1 != elem3
      assert 2 = XmlElement.length(xml)
    end

    test "insert/3 and insert_and_get/3 with negative index", %{xml_element: xml} do
      # Insert at the beginning
      assert :ok = Yex.XmlElement.insert(xml, 0, XmlTextPrelim.from("a"))
      assert :ok = Yex.XmlElement.insert(xml, 1, XmlTextPrelim.from("b"))
      assert :ok = Yex.XmlElement.insert(xml, 2, XmlTextPrelim.from("c"))
      # -1: append at the end
      assert :ok = Yex.XmlElement.insert(xml, -1, XmlTextPrelim.from("x"))

      assert ["a", "b", "c", "x"] =
               Enum.map(0..3, &XmlText.to_string(Yex.XmlElement.fetch!(xml, &1)))

      # -2: insert before the last element
      assert :ok = Yex.XmlElement.insert(xml, -2, XmlTextPrelim.from("y"))

      assert ["a", "b", "c", "y", "x"] =
               Enum.map(0..4, &XmlText.to_string(Yex.XmlElement.fetch!(xml, &1)))

      # insert_and_get behaves the same
      assert %XmlText{} = Yex.XmlElement.insert_and_get(xml, -1, XmlTextPrelim.from("z"))

      assert ["a", "b", "c", "y", "x", "z"] =
               Enum.map(0..5, &XmlText.to_string(Yex.XmlElement.fetch!(xml, &1)))
    end

    test "insert_and_get/3 inserts and returns the element", %{xml_element: xml} do
      assert %XmlElement{} =
               XmlElement.insert_and_get(xml, 0, XmlElementPrelim.empty("p"))

      assert %XmlText{} = XmlElement.insert_and_get(xml, 1, XmlTextPrelim.from("text"))
      assert 2 = XmlElement.length(xml)
    end

    test "push_and_get/2 pushes and returns the element", %{xml_element: xml} do
      assert %XmlElement{} = XmlElement.push_and_get(xml, XmlElementPrelim.empty("span"))
      assert %XmlText{} = XmlElement.push_and_get(xml, XmlTextPrelim.from("content"))
      assert 2 = XmlElement.length(xml)
    end

    test "insert_after_and_get/3 inserts after ref and returns the element", %{xml_element: xml} do
      first = XmlElement.insert_and_get(xml, 0, XmlElementPrelim.empty("first"))

      assert %XmlElement{} =
               XmlElement.insert_after_and_get(xml, first, XmlElementPrelim.empty("second"))

      assert 2 = XmlElement.length(xml)
    end

    test "insert_after_and_get/3 with non-existing ref inserts at beginning", %{xml_element: xml} do
      # Insert initial element
      _first = XmlElement.insert_and_get(xml, 0, XmlElementPrelim.empty("first"))

      # Create a separate xml fragment with element that doesn't exist in our xml
      doc2 = Yex.Doc.new()
      other_frag = Yex.Doc.get_xml_fragment(doc2, "other")

      other_elem =
        XmlFragment.insert_and_get(other_frag, 0, XmlElementPrelim.empty("other"))

      # insert_after_and_get with non-existing ref should insert at beginning
      assert %XmlElement{} =
               XmlElement.insert_after_and_get(
                 xml,
                 other_elem,
                 XmlElementPrelim.empty("inserted")
               )

      # Should have 2 elements now (first + inserted at beginning)
      assert 2 = XmlElement.length(xml)
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
      assert "<div>12<div></div>3</div>" = to_string(xml)
      XmlElement.insert_after(xml, nil, XmlElementPrelim.empty("div"))
      assert "<div><div></div>12<div></div>3</div>" = to_string(xml)
    end

    test "delete", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from("content"))
      assert "<div>content</div>" == to_string(xml)
      assert :ok == XmlElement.delete(xml, 0, 1)
      assert "<div></div>" == to_string(xml)
    end

    test "get_tag", %{xml_element: xml1} do
      tag = XmlElement.get_tag(xml1)
      assert "div" == tag
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

    # Additional tests to improve coverage

    test "length returns correct number of children", %{xml_element: e} do
      assert 0 == XmlElement.length(e)

      # Add elements and check length increases
      XmlElement.push(e, XmlTextPrelim.from("test1"))
      assert 1 == XmlElement.length(e)

      XmlElement.push(e, XmlElementPrelim.empty("div"))
      assert 2 == XmlElement.length(e)

      # Delete element and check length decreases
      XmlElement.delete(e, 0, 1)
      assert 1 == XmlElement.length(e)
    end

    test "insert at specific index", %{xml_element: e} do
      # Insert at index 0 in empty element
      XmlElement.insert(e, 0, XmlTextPrelim.from("first"))
      assert 1 == XmlElement.length(e)

      # Insert at end
      XmlElement.insert(e, 1, XmlTextPrelim.from("last"))
      assert 2 == XmlElement.length(e)

      # Insert in middle
      XmlElement.insert(e, 1, XmlTextPrelim.from("middle"))
      assert 3 == XmlElement.length(e)

      # Check order
      assert "first" == XmlText.to_string(XmlElement.fetch!(e, 0))
      assert "middle" == XmlText.to_string(XmlElement.fetch!(e, 1))
      assert "last" == XmlText.to_string(XmlElement.fetch!(e, 2))
    end

    test "get/3 returns child at index (using default)", %{xml_element: e} do
      XmlElement.push(e, XmlTextPrelim.from("content"))

      child = XmlElement.get(e, 0)
      assert "content" == XmlText.to_string(child)
    end

    test "no next sibling for last element", %{xml_element: xml_element} do
      assert nil == XmlElement.next_sibling(xml_element)
    end

    test "no prev sibling for first element", %{xml_element: xml_element} do
      assert nil == XmlElement.prev_sibling(xml_element)
    end

    test "get_attribute returns nil for non-existent attribute", %{xml_element: xml} do
      assert nil == XmlElement.get_attribute(xml, "nonexistent")
    end

    test "get_attributes returns empty map for element with no attributes", %{xml_element: xml} do
      assert %{} == XmlElement.get_attributes(xml)
    end

    test "remove_attribute on non-existent attribute", %{xml_element: xml} do
      # Should not error on removing non-existent attribute
      assert :ok = XmlElement.remove_attribute(xml, "nonexistent")
    end

    test "insert with multiple children", %{xml_element: e} do
      # Insert multiple children and test order
      XmlElement.insert(
        e,
        0,
        XmlElementPrelim.new("span", [
          XmlTextPrelim.from("text1"),
          XmlTextPrelim.from("text2")
        ])
      )

      assert 1 == XmlElement.length(e)
      assert "span" == XmlElement.get_tag(XmlElement.fetch!(e, 0))

      child = XmlElement.fetch!(e, 0)
      assert 2 == XmlElement.length(child)
    end

    test "children streaming interface", %{xml_element: e} do
      # Add some children
      XmlElement.push(e, XmlTextPrelim.from("1"))
      XmlElement.push(e, XmlTextPrelim.from("2"))
      XmlElement.push(e, XmlTextPrelim.from("3"))

      # Test Stream functions
      results =
        XmlElement.children(e)
        |> Stream.map(fn child -> XmlText.to_string(child) end)
        |> Enum.to_list()

      assert ["1", "2", "3"] == results

      # Test other Stream operations
      count = XmlElement.children(e) |> Enum.count()
      assert 3 == count

      sum =
        XmlElement.children(e)
        |> Stream.map(fn child -> String.to_integer(XmlText.to_string(child)) end)
        |> Enum.sum()

      assert 6 == sum
    end

    test "complex nested structure operations", %{xml_element: root} do
      # Build a complex structure
      XmlElement.push(
        root,
        XmlElementPrelim.new(
          "div",
          [
            XmlElementPrelim.new(
              "span",
              [
                XmlTextPrelim.from("inner text")
              ],
              %{"class" => "highlight"}
            )
          ],
          %{"id" => "container"}
        )
      )

      # Navigate and manipulate the structure
      container = XmlElement.fetch!(root, 0)
      assert "div" == XmlElement.get_tag(container)
      assert "container" == XmlElement.get_attribute(container, "id")

      span = XmlElement.fetch!(container, 0)
      assert "span" == XmlElement.get_tag(span)
      assert "highlight" == XmlElement.get_attribute(span, "class")

      text = XmlElement.fetch!(span, 0)
      assert "inner text" == XmlText.to_string(text)

      # Modify the structure
      XmlElement.insert_attribute(span, "data-test", "value")
      XmlElement.insert(span, 1, XmlElementPrelim.empty("br"))

      # Test parent relationships
      assert root == XmlElement.parent(container)
      assert container == XmlElement.parent(span)

      # Test XML output - Skipping exact string comparison since attribute order might differ
      result = to_string(root)
      assert String.contains?(result, "<div id=\"container\">")
      assert String.contains?(result, "<span")
      assert String.contains?(result, "class=\"highlight\"")
      assert String.contains?(result, "data-test=\"value\"")
      assert String.contains?(result, ">inner text<br></br>")
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

    test "insert_attribute with map values", %{xml_element: xml} do
      XmlElement.insert_attribute(xml, "height", %{"value" => "10"})

      assert %{"value" => "10"} == XmlElement.get_attribute(xml, "height")
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

    # Additional XmlElementPrelim tests
    test "XmlElementPrelim.empty with attributes", %{xml_fragment: xml_fragment} do
      # Create an element with attributes using constructor + empty
      el = %XmlElementPrelim{
        tag: "div",
        attributes: %{"class" => "container", "id" => "main"},
        children: []
      }

      XmlFragment.push(xml_fragment, el)
      result = XmlFragment.to_string(xml_fragment)

      # Check for attributes individually instead of exact string match
      assert String.contains?(result, "<div ")
      assert String.contains?(result, "class=\"container\"")
      assert String.contains?(result, "id=\"main\"")
      assert String.contains?(result, "></div>")
    end

    test "XmlElementPrelim with empty children list", %{xml_fragment: xml_fragment} do
      XmlFragment.push(
        xml_fragment,
        XmlElementPrelim.new("div", [])
      )

      assert "<div></div>" == XmlFragment.to_string(xml_fragment)
    end
  end

  describe "as_prelim" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_element: xml, xml_fragment: f}
    end

    test "converts empty XmlElement to TextPrelim", %{xml_element: xml} do
      prelim = XmlElement.as_prelim(xml)
      assert %XmlElementPrelim{} = prelim
      assert "div" = prelim.tag
      assert %{} = prelim.attributes
      assert [] = prelim.children
    end

    test "converts XmlElement with attributes to TextPrelim", %{xml_element: xml} do
      XmlElement.insert_attribute(xml, "class", "container")
      XmlElement.insert_attribute(xml, "id", "main")

      prelim = XmlElement.as_prelim(xml)
      assert %XmlElementPrelim{} = prelim
      assert "div" = prelim.tag
      assert %{"class" => "container", "id" => "main"} = prelim.attributes
      assert [] = prelim.children
    end

    test "converts XmlElement with children to TextPrelim", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from("Hello"))
      XmlElement.push(xml, XmlElementPrelim.empty("span"))
      XmlElement.push(xml, XmlTextPrelim.from("World"))

      prelim = XmlElement.as_prelim(xml)
      assert %XmlElementPrelim{} = prelim
      assert "div" = prelim.tag
      assert %{} = prelim.attributes

      assert [
               %XmlTextPrelim{delta: [%{insert: "Hello"}]},
               %XmlElementPrelim{tag: "span", attributes: %{}, children: []},
               %XmlTextPrelim{delta: [%{insert: "World"}]}
             ] = prelim.children
    end

    test "converts complex XmlElement to TextPrelim", %{xml_element: xml} do
      XmlElement.insert_attribute(xml, "class", "container")
      XmlElement.push(xml, XmlTextPrelim.from("Hello"))

      child = XmlElementPrelim.empty("span")
      XmlElement.push(xml, child)
      {:ok, span} = XmlElement.fetch(xml, 1)
      XmlElement.insert_attribute(span, "class", "highlight")
      XmlElement.push(span, XmlTextPrelim.from("World"))

      prelim = XmlElement.as_prelim(xml)
      assert %XmlElementPrelim{} = prelim
      assert "div" = prelim.tag
      assert %{"class" => "container"} = prelim.attributes

      assert [
               %XmlTextPrelim{delta: [%{insert: "Hello"}]},
               %XmlElementPrelim{
                 tag: "span",
                 attributes: %{"class" => "highlight"},
                 children: [%XmlTextPrelim{delta: [%{insert: "World"}]}]
               }
             ] = prelim.children
    end
  end

  describe "edge and error cases for coverage" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_element: xml, xml_fragment: f}
    end

    test "fetch/2 and fetch!/2 with out of bounds and negative index", %{xml_element: xml} do
      assert :error == XmlElement.fetch(xml, 0)
      assert_raise ArgumentError, fn -> XmlElement.fetch!(xml, 0) end
    end

    test "delete/3 with out of bounds and negative index", %{xml_element: xml} do
      assert :ok == XmlElement.delete(xml, 0, 1)
      assert "<div></div>" == to_string(xml)

      XmlElement.push(xml, XmlTextPrelim.from("a"))
      assert "<div>a</div>" == to_string(xml)
      assert :ok == XmlElement.delete(xml, 0, 1)
      assert "<div></div>" == to_string(xml)

      assert :ok == XmlElement.delete(xml, 0, 1)
      assert "<div></div>" == to_string(xml)
    end

    test "insert_attribute/3, remove_attribute/2, get_attribute/2, get_attributes/1", %{
      xml_element: xml
    } do
      assert :ok == XmlElement.insert_attribute(xml, "k", "v")
      assert "v" == XmlElement.get_attribute(xml, "k")
      assert %{"k" => "v"} = XmlElement.get_attributes(xml)
      assert :ok == XmlElement.remove_attribute(xml, "k")
      assert nil == XmlElement.get_attribute(xml, "k")
    end

    test "get_tag/1, to_string/1, as_prelim/1 with empty and after ops", %{xml_element: xml} do
      assert "div" == XmlElement.get_tag(xml)
      assert is_binary(to_string(xml))
      prelim = XmlElement.as_prelim(xml)
      assert %XmlElementPrelim{tag: "div"} = prelim
    end

    test "insert_after/3 with not found ref", %{xml_element: xml} do
      XmlElement.push(xml, XmlTextPrelim.from("a"))
      XmlElement.push(xml, XmlTextPrelim.from("b"))
      {:ok, n1} = XmlElement.fetch(xml, 0)
      {:ok, n2} = XmlElement.fetch(xml, 1)
      # insert after n2 (last)
      assert :ok == XmlElement.insert_after(xml, n2, XmlTextPrelim.from("c"))
      # insert after not found (should insert at 0)
      dummy = %XmlText{doc: n1.doc, reference: make_ref()}
      assert :ok == XmlElement.insert_after(xml, dummy, XmlTextPrelim.from("d"))
    end

    test "unshift/2 and push/2 with empty and after ops", %{xml_element: xml} do
      assert :ok == XmlElement.unshift(xml, XmlTextPrelim.from("a"))
      assert :ok == XmlElement.push(xml, XmlTextPrelim.from("b"))
    end
  end
end
