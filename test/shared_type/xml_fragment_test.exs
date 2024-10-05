defmodule YexXmlFragmentTest do
  use ExUnit.Case
  alias Yex.{Doc, XmlFragment, XmlElement, XmlElementPrelim, XmlText, XmlTextPrelim, SharedType}
  doctest XmlFragment
  doctest Yex.XmlFragmentPrelim

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

    test "insert_after", %{xml_fragment: f} do
      XmlFragment.push(f, XmlTextPrelim.from("1"))
      XmlFragment.push(f, XmlTextPrelim.from("2"))
      XmlFragment.push(f, XmlTextPrelim.from("3"))
      assert text2 = XmlFragment.fetch!(f, 1)
      XmlFragment.insert_after(f, text2, XmlElementPrelim.empty("div"))
      assert "12<div></div>3" = XmlFragment.to_string(f)
      XmlFragment.insert_after(f, nil, XmlElementPrelim.empty("div"))
      assert "<div></div>12<div></div>3" = XmlFragment.to_string(f)
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
end
