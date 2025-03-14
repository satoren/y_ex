defmodule YexXmlTextTest do
  use ExUnit.Case
  alias Yex.{Doc, XmlFragment, XmlText, XmlTextPrelim, SharedType}
  doctest XmlText
  doctest XmlTextPrelim

  describe "xml_text" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_text: xml, xml_fragment: f}
    end

    test "Delete", %{xml_text: text} do
      XmlText.insert(text, 0, "1234")
      XmlText.insert(text, 5, "5", %{"bold" => true})

      delta = [
        %{
          "delete" => 3
        }
      ]

      XmlText.apply_delta(text, delta)
      assert "4<bold>5</bold>" == XmlText.to_string(text)

      assert [%{insert: "4"}, %{attributes: %{"bold" => true}, insert: "5"}] ==
               XmlText.to_delta(text)
    end

    test "Retain", %{xml_text: text} do
      delta = [
        %{
          retain: 1
        },
        %{
          delete: 3
        }
      ]

      XmlText.insert(text, 0, "12345")
      XmlText.apply_delta(text, delta)
      assert "15" == XmlText.to_string(text)

      assert [%{insert: "15"}] ==
               XmlText.to_delta(text)
    end

    test "Insert", %{xml_text: text} do
      delta = [
        %{
          "retain" => 1
        },
        %{
          "insert" => "abc",
          "attributes" => %{"bold" => true}
        },
        %{
          "retain" => 1
        },
        %{
          "insert" => "xyz"
        }
      ]

      XmlText.insert(text, 0, "123")
      XmlText.apply_delta(text, delta)

      assert [
               %{insert: "1"},
               %{insert: "abc", attributes: %{"bold" => true}},
               %{insert: "2xyz3"}
             ] ==
               XmlText.to_delta(text)
    end

    test "Retain (on Yex.XmlText)", %{xml_text: text} do
      delta = [
        %{
          "retain" => 5,
          "attributes" => %{"italic" => true}
        }
      ]

      XmlText.insert(text, 0, "123456")
      XmlText.apply_delta(text, delta)

      assert [%{insert: "12345", attributes: %{"italic" => true}}, %{insert: "6"}] ==
               XmlText.to_delta(text)
    end

    test "delete", %{xml_text: text} do
      delta = [
        %{
          "retain" => 3,
          "attributes" => %{"italic" => true}
        }
      ]

      XmlText.insert(text, 0, "123456")
      XmlText.apply_delta(text, delta)
      XmlText.delete(text, 2, 2)

      assert [%{insert: "12", attributes: %{"italic" => true}}, %{insert: "56"}] ==
               XmlText.to_delta(text)
    end

    test "delete with minus", %{xml_text: text} do
      XmlText.insert(text, 0, "123456")

      assert "123456" == XmlText.to_string(text)
      assert :ok == XmlText.delete(text, -1, 1)
      assert "12345" == XmlText.to_string(text)
    end

    test "format", %{xml_text: text} do
      XmlText.insert(text, 0, "123456")
      XmlText.format(text, 1, 3, %{"bold" => true})

      assert [%{insert: "1"}, %{insert: "234", attributes: %{"bold" => true}}, %{insert: "56"}] ==
               XmlText.to_delta(text)
    end

    test "next_sibling", %{xml_text: text, xml_fragment: xml_fragment} do
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_next_content"))
      next = XmlText.next_sibling(text)
      next_next = XmlText.next_sibling(next)

      assert "next_content" == XmlText.to_string(next)
      assert "next_next_content" == XmlText.to_string(next_next)
    end

    test "prev_sibling", %{xml_text: text, xml_fragment: xml_fragment} do
      XmlText.insert(text, 0, "content")
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_next_content"))
      next = XmlText.next_sibling(text)
      next_prev = XmlText.prev_sibling(next)

      assert "content" == XmlText.to_string(next_prev)
    end

    test "parent", %{xml_text: text, xml_fragment: xml_fragment} do
      parent = Yex.Xml.parent(text)

      assert parent == xml_fragment
    end

    test "observe", %{doc: doc, xml_text: text} do
      ref = SharedType.observe(text)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlText.insert(text, 0, "123456")
          XmlText.format(text, 1, 3, %{"bold" => true})
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlTextEvent{
                        target: ^text,
                        delta: [
                          %{insert: "1"},
                          %{attributes: %{"bold" => true}, insert: "234"},
                          %{insert: "56"}
                        ]
                      }, "origin_value", nil}
    end

    test "observe delete ", %{doc: doc, xml_text: text} do
      XmlText.insert(text, 0, "123456")
      ref = SharedType.observe(text)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlText.delete(text, 0, 1)
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlTextEvent{
                        target: ^text,
                        delta: [%{delete: 1}],
                        path: []
                      }, "origin_value", nil}
    end

    test "observe_deep", %{doc: doc, xml_text: text} do
      ref = SharedType.observe_deep(text)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          XmlText.insert(text, 0, "123456")
          XmlText.format(text, 1, 3, %{"bold" => true})
        end)

      assert_receive {:observe_deep_event, ^ref,
                      [
                        %Yex.XmlTextEvent{
                          path: [],
                          target: ^text,
                          delta: [
                            %{insert: "1"},
                            %{attributes: %{"bold" => true}, insert: "234"},
                            %{insert: "56"}
                          ]
                        }
                      ], "origin_value", _metadata}
    end
  end

  describe "as_prelim" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlTextPrelim.from(""))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_text: xml, xml_fragment: f}
    end

    test "converts empty XmlText to TextPrelim", %{xml_text: text} do
      prelim = XmlText.as_prelim(text)
      assert %XmlTextPrelim{} = prelim
      assert [] = prelim.delta
    end

    test "converts XmlText with content to TextPrelim", %{xml_text: text} do
      XmlText.insert(text, 0, "Hello World")

      prelim = XmlText.as_prelim(text)
      assert %XmlTextPrelim{} = prelim
      assert [%{insert: "Hello World"}] = prelim.delta
    end

    test "converts XmlText with formatted content to TextPrelim", %{xml_text: text} do
      XmlText.insert(text, 0, "Hello World")
      XmlText.format(text, 0, 5, %{"bold" => true})
      XmlText.format(text, 6, 5, %{"italic" => true})

      prelim = XmlText.as_prelim(text)
      assert %XmlTextPrelim{} = prelim

      assert [
               %{attributes: %{"bold" => true}, insert: "Hello"},
               %{insert: " "},
               %{attributes: %{"italic" => true}, insert: "World"}
             ] = prelim.delta
    end

    test "converts XmlText with complex formatting to TextPrelim", %{xml_text: text} do
      XmlText.insert(text, 0, "Hello World")
      XmlText.format(text, 0, 5, %{"bold" => true})
      XmlText.format(text, 6, 5, %{"italic" => true})
      XmlText.format(text, 0, 11, %{"color" => "red"})

      prelim = XmlText.as_prelim(text)
      assert %XmlTextPrelim{} = prelim

      assert [
               %{insert: "Hello", attributes: %{"bold" => true, "color" => "red"}},
               %{insert: " ", attributes: %{"color" => "red"}},
               %{insert: "World", attributes: %{"italic" => true, "color" => "red"}}
             ] = prelim.delta
    end
  end
end
