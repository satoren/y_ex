defmodule YexXmlFragmentTest do
  use ExUnit.Case

  alias Yex.{
    Doc,
    XmlFragment,
    XmlElement,
    XmlElementPrelim,
    XmlText,
    XmlTextPrelim,
    XmlFragmentPrelim,
    SharedType
  }

  doctest XmlFragment
  doctest Yex.XmlFragmentPrelim

  setup do
    doc = Doc.with_options(%Doc.Options{client_id: 1})
    f = Doc.get_xml_fragment(doc, "xml")
    %{doc: doc, xml_fragment: f}
  end

  describe "xml_fragment" do
    @doc """
    Tests behavior of `insert/3` and `insert_and_get/3` when given negative indices.
    - `-1`: append at the end
    - `-2`: insert before the last element
    """
    test "insert/3 and insert_and_get/3 with negative index", %{xml_fragment: frag} do
      # Insert at the beginning
      assert :ok = Yex.XmlFragment.insert(frag, 0, XmlTextPrelim.from("a"))
      assert :ok = Yex.XmlFragment.insert(frag, 1, XmlTextPrelim.from("b"))
      assert :ok = Yex.XmlFragment.insert(frag, 2, XmlTextPrelim.from("c"))
      # -1: append at the end
      assert :ok = Yex.XmlFragment.insert(frag, -1, XmlTextPrelim.from("x"))

      assert ["a", "b", "c", "x"] =
               Enum.map(0..3, &XmlText.to_string(Yex.XmlFragment.fetch!(frag, &1)))

      # -2: insert before the last element
      assert :ok = Yex.XmlFragment.insert(frag, -2, XmlTextPrelim.from("y"))

      assert ["a", "b", "c", "y", "x"] =
               Enum.map(0..4, &XmlText.to_string(Yex.XmlFragment.fetch!(frag, &1)))

      # insert_and_get behaves the same
      assert %XmlText{} = Yex.XmlFragment.insert_and_get(frag, -1, XmlTextPrelim.from("z"))

      assert ["a", "b", "c", "y", "x", "z"] =
               Enum.map(0..5, &XmlText.to_string(Yex.XmlFragment.fetch!(frag, &1)))
    end

    test "push", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlFragment.fetch(f, 0)
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlFragment.fetch(f, 1)
    end

    test "push_and_get/2 pushes and returns the element", %{xml_fragment: f} do
      assert %XmlText{} = XmlFragment.push_and_get(f, XmlTextPrelim.from("text"))
      assert %XmlElement{} = XmlFragment.push_and_get(f, XmlElementPrelim.empty("div"))
      assert 2 = XmlFragment.length(f)
    end

    test "insert_and_get/3 inserts and returns the element", %{xml_fragment: f} do
      assert %XmlElement{} =
               XmlFragment.insert_and_get(f, 0, XmlElementPrelim.empty("p"))

      assert %XmlText{} = XmlFragment.insert_and_get(f, 1, XmlTextPrelim.from("text"))
      assert 2 = XmlFragment.length(f)
    end

    test "insert_after_and_get/3 inserts after ref and returns the element", %{xml_fragment: f} do
      first = XmlFragment.insert_and_get(f, 0, XmlElementPrelim.empty("first"))

      assert %XmlElement{} =
               XmlFragment.insert_after_and_get(f, first, XmlElementPrelim.empty("second"))

      assert 2 = XmlFragment.length(f)
    end

    test "insert_after_and_get/3 with non-existing ref inserts at beginning", %{xml_fragment: f} do
      # Insert initial element
      _first = XmlFragment.insert_and_get(f, 0, XmlElementPrelim.empty("first"))

      # Create a separate xml fragment with element that doesn't exist in our fragment
      doc2 = Yex.Doc.new()
      other_frag = Yex.Doc.get_xml_fragment(doc2, "other")

      other_elem =
        XmlFragment.insert_and_get(other_frag, 0, XmlElementPrelim.empty("other"))

      # insert_after_and_get with non-existing ref should insert at beginning
      assert %XmlElement{} =
               XmlFragment.insert_after_and_get(f, other_elem, XmlElementPrelim.empty("inserted"))

      # Should have 2 elements now (first + inserted at beginning)
      assert 2 = XmlFragment.length(f)
    end

    test "unshift", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, %XmlText{}} = XmlFragment.fetch(f, 0)
      XmlFragment.unshift(f, XmlElementPrelim.empty("div"))
      {:ok, %XmlElement{}} = XmlFragment.fetch(f, 0)
    end

    test "insert_after", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("1"))
      XmlFragment.push(f, XmlTextPrelim.from("2"))
      XmlFragment.push(f, XmlTextPrelim.from("3"))
      assert text2 = XmlFragment.fetch!(f, 1)
      XmlFragment.insert_after(f, text2, XmlElementPrelim.empty("div"))
      assert "12<div></div>3" = to_string(f)
      XmlFragment.insert_after(f, nil, XmlElementPrelim.empty("div"))
      assert "<div></div>12<div></div>3" = to_string(f)
    end

    test "compare", %{xml_fragment: f} do
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      XmlFragment.push(f, XmlElementPrelim.empty("div"))
      xml1 = XmlFragment.fetch!(f, 0)
      xml2 = XmlFragment.fetch!(f, 0)

      assert xml1 == xml2
      xml3 = XmlFragment.fetch!(f, 1)
      assert xml1 != xml3
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

    test "get/3 returns element or default", %{xml_fragment: xml} do
      XmlFragment.push(xml, XmlElementPrelim.empty("div"))

      assert %XmlElement{} = XmlFragment.get(xml, 0)
      assert nil == XmlFragment.get(xml, 1)
      assert :default == XmlFragment.get(xml, 1, :default)
    end

    test "get_lazy/3 returns element or evaluates function", %{xml_fragment: xml} do
      XmlFragment.push(xml, XmlElementPrelim.empty("div"))

      # Existing element
      assert %XmlElement{} = XmlFragment.get_lazy(xml, 0, fn -> :not_called end)

      # Non-existing element - function is called
      assert :default ==
               XmlFragment.get_lazy(xml, 1, fn -> :default end)

      # Function should only be called when needed
      called = make_ref()

      XmlFragment.get_lazy(xml, 0, fn ->
        send(self(), called)
        :not_called
      end)

      refute_received ^called

      XmlFragment.get_lazy(xml, 1, fn ->
        send(self(), called)
        :called
      end)

      assert_received ^called
    end

    test "get_lazy/3 with *_and_get for get-or-create pattern", %{xml_fragment: xml} do
      # Get or create pattern
      elem1 =
        XmlFragment.get_lazy(xml, 0, fn ->
          XmlFragment.push_and_get(xml, XmlElementPrelim.empty("div"))
        end)

      assert %XmlElement{} = elem1
      assert 1 = XmlFragment.length(xml)

      # Second call should return existing element, not create new one
      elem2 =
        XmlFragment.get_lazy(xml, 0, fn ->
          XmlFragment.push_and_get(xml, XmlElementPrelim.empty("span"))
        end)

      assert elem1 == elem2
      assert 1 = XmlFragment.length(xml)

      # Different index creates new element
      elem3 =
        XmlFragment.get_lazy(xml, 1, fn ->
          XmlFragment.push_and_get(xml, XmlElementPrelim.empty("p"))
        end)

      assert %XmlElement{} = elem3
      assert elem1 != elem3
      assert 2 = XmlFragment.length(xml)
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
      assert "test<div></div>" = to_string(f)
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

    test "parent", %{xml_fragment: f} do
      assert nil == XmlFragment.parent(f)
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

    test "observe", %{doc: doc, xml_fragment: f} do
      ref = SharedType.observe(f)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlFragment.push(f, XmlTextPrelim.from("test"))
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlEvent{
                        target: ^f,
                        keys: %{},
                        delta: [
                          %{insert: [%Yex.XmlText{}]}
                        ]
                      }, "origin_value", nil}
    end

    test "observe delete ", %{doc: doc, xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("Hello"))
      XmlFragment.push(f, XmlTextPrelim.from("World"))

      ref = SharedType.observe(f)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlFragment.delete(f, 0, 1)
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlEvent{
                        target: ^f,
                        keys: %{},
                        delta: [%{delete: 1}],
                        path: []
                      }, "origin_value", nil}
    end

    test "observe_deep", %{doc: doc, xml_fragment: f} do
      XmlFragment.push(
        f,
        XmlElementPrelim.new("span", [
          XmlElementPrelim.new("span", [
            XmlTextPrelim.from("text")
          ])
        ])
      )

      el2 = XmlFragment.first_child(f)
      el3 = XmlElement.first_child(el2)
      text = XmlElement.first_child(el3)

      ref = SharedType.observe_deep(f)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlFragment.push(f, XmlTextPrelim.from("1"))
          XmlElement.insert_attribute(el2, "attr", "value")
          XmlElement.push(el3, XmlElementPrelim.empty("div"))
          XmlText.insert(text, 0, "text")
        end)

      assert_receive {:observe_deep_event, ^ref,
                      [
                        %Yex.XmlEvent{
                          path: [],
                          target: ^f,
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

  describe "as_prelim" do
    test "converts empty XmlFragment to TextPrelim", %{xml_fragment: f} do
      prelim = XmlFragment.as_prelim(f)
      assert %XmlFragmentPrelim{} = prelim
      assert [] = prelim.children
    end

    test "converts XmlFragment with single element to TextPrelim", %{xml_fragment: f} do
      element = XmlElementPrelim.empty("div")
      XmlFragment.push(f, element)
      {:ok, div} = XmlFragment.fetch(f, 0)
      XmlElement.insert_attribute(div, "class", "container")

      prelim = XmlFragment.as_prelim(f)
      assert %XmlFragmentPrelim{} = prelim

      assert [
               %XmlElementPrelim{
                 tag: "div",
                 attributes: %{"class" => "container"},
                 children: []
               }
             ] = prelim.children
    end

    test "converts XmlFragment with multiple elements to TextPrelim", %{xml_fragment: f} do
      element1 = XmlElementPrelim.empty("div")
      XmlFragment.push(f, element1)
      {:ok, div1} = XmlFragment.fetch(f, 0)
      XmlElement.insert_attribute(div1, "class", "item")

      element2 = XmlElementPrelim.empty("span")
      XmlFragment.push(f, element2)
      {:ok, span} = XmlFragment.fetch(f, 1)
      XmlElement.insert_attribute(span, "class", "highlight")
      XmlElement.push(span, XmlTextPrelim.from("Hello"))

      prelim = XmlFragment.as_prelim(f)
      assert %XmlFragmentPrelim{} = prelim

      assert [
               %XmlElementPrelim{
                 tag: "div",
                 attributes: %{"class" => "item"},
                 children: []
               },
               %XmlElementPrelim{
                 tag: "span",
                 attributes: %{"class" => "highlight"},
                 children: [%XmlTextPrelim{delta: [%{insert: "Hello"}]}]
               }
             ] = prelim.children
    end

    test "converts complex XmlFragment to TextPrelim", %{xml_fragment: f} do
      element1 = XmlElementPrelim.empty("div")
      XmlFragment.push(f, element1)
      {:ok, div1} = XmlFragment.fetch(f, 0)
      XmlElement.insert_attribute(div1, "class", "container")

      XmlElement.push(div1, XmlTextPrelim.from("Hello"))

      element2 = XmlElementPrelim.empty("span")
      XmlElement.push(div1, element2)
      {:ok, span} = XmlElement.fetch(div1, 1)
      XmlElement.insert_attribute(span, "class", "highlight")
      XmlElement.push(span, XmlTextPrelim.from("World"))

      prelim = XmlFragment.as_prelim(f)
      assert %XmlFragmentPrelim{} = prelim

      assert [
               %XmlElementPrelim{
                 tag: "div",
                 attributes: %{"class" => "container"},
                 children: [
                   %XmlTextPrelim{delta: [%{insert: "Hello"}]},
                   %XmlElementPrelim{
                     tag: "span",
                     attributes: %{"class" => "highlight"},
                     children: [%XmlTextPrelim{delta: [%{insert: "World"}]}]
                   }
                 ]
               }
             ] = prelim.children
    end

    test "Yex.Output protocol delegates to XmlFragment.as_prelim", %{xml_fragment: f} do
      # Ensure protocol implementation is exercised
      assert Yex.Output.as_prelim(f) == XmlFragment.as_prelim(f)
    end

    test "load blocknote_data.bin and as_prelim" do
      path = Path.expand("../test_data/blocknote_data.bin", __DIR__)
      {:ok, bin} = File.read(path)
      doc = Yex.Doc.new()
      Yex.apply_update(doc, bin)
      prelim = Yex.Doc.get_xml_fragment(doc, "document-store") |> Yex.Output.as_prelim()

      new_doc = Yex.Doc.new()
      frag = Yex.Doc.get_xml_fragment(new_doc, "document-store")

      Enum.each(prelim.children, fn child ->
        Yex.XmlFragment.insert(frag, Yex.XmlFragment.length(frag), child)
      end)

      assert frag |> Yex.Output.as_prelim() == prelim
    end
  end
end
