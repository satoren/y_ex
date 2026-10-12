defmodule YexXmlTextTest do
  use ExUnit.Case, async: true
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
      assert "4<bold>5</bold>" == to_string(text)

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
      assert "15" == to_string(text)

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

      assert "123456" == to_string(text)
      assert :ok == XmlText.delete(text, -1, 1)
      assert "12345" == to_string(text)
    end

    test "format", %{xml_text: text} do
      XmlText.insert(text, 0, "123456")
      XmlText.format(text, 1, 3, %{"bold" => true})

      assert [%{insert: "1"}, %{insert: "234", attributes: %{"bold" => true}}, %{insert: "56"}] ==
               XmlText.to_delta(text)
    end

    test "insert_embed", %{xml_text: text} do
      XmlText.insert(text, 0, "abcd")
      embed = XmlText.quote(text, 1, 2)

      assert :ok == XmlText.insert_embed(text, 4, embed)

      assert Enum.any?(XmlText.to_delta(text), fn
               %{insert: %Yex.WeakLink{}} -> true
               _ -> false
             end)
    end

    test "insert_embed with attributes", %{xml_text: text} do
      XmlText.insert(text, 0, "abcd")
      embed = XmlText.quote(text, 1, 2)

      assert :ok == XmlText.insert_embed(text, 4, embed, %{"bold" => true})

      assert Enum.any?(XmlText.to_delta(text), fn
               %{insert: %Yex.WeakLink{}, attributes: %{"bold" => true}} -> true
               _ -> false
             end)
    end

    test "next_sibling", %{xml_text: text, xml_fragment: xml_fragment} do
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_next_content"))
      next = XmlText.next_sibling(text)
      next_next = XmlText.next_sibling(next)

      assert "next_content" == to_string(next)
      assert "next_next_content" == to_string(next_next)
    end

    test "prev_sibling", %{xml_text: text, xml_fragment: xml_fragment} do
      XmlText.insert(text, 0, "content")
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_content"))
      XmlFragment.push(xml_fragment, XmlTextPrelim.from("next_next_content"))
      next = XmlText.next_sibling(text)
      next_prev = XmlText.prev_sibling(next)

      assert "content" == to_string(next_prev)
    end

    test "parent", %{xml_text: text, xml_fragment: xml_fragment} do
      parent = Yex.Xml.parent(text)

      assert parent == xml_fragment
    end

    test "length", %{xml_text: text} do
      XmlText.insert(text, 0, "abcd")
      assert XmlText.length(text) == 4
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

  describe "XmlTextPrelim" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      %{doc: d1, xml_fragment: f}
    end

    test "insert prelim with any attribute types", %{xml_fragment: xml_fragment} do
      assert :ok =
               XmlFragment.insert(xml_fragment, 0, %Yex.XmlTextPrelim{
                 delta: [
                   %{
                     attributes: %{
                       "link" => %{
                         "class" => nil,
                         "indentation" => 0,
                         "itemType" => <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>,
                         "lineHeight" => 1.5,
                         "array" => [1, 2, 3],
                         "href" => "http://google.com",
                         "rel" => "noopener noreferrer nofollow",
                         "target" => "_blank"
                       }
                     },
                     insert: "http://google.com"
                   }
                 ],
                 attributes: %{}
               })

      {:ok, text} = XmlFragment.fetch(xml_fragment, 0)

      assert [
               %{
                 insert: "http://google.com",
                 attributes: %{
                   "link" => %{
                     "class" => nil,
                     "indentation" => 0,
                     "itemType" => <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>,
                     "lineHeight" => 1.5,
                     "array" => [1, 2, 3],
                     "href" => "http://google.com",
                     "rel" => "noopener noreferrer nofollow",
                     "target" => "_blank"
                   }
                 }
               }
             ] == Yex.XmlText.to_delta(text)
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

  describe "quote" do
    setup do
      d1 = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(d1, "xml")
      XmlFragment.push(f, XmlTextPrelim.from("Hello"))
      {:ok, xml} = XmlFragment.fetch(f, 0)
      %{doc: d1, xml_text: xml, xml_fragment: f}
    end

    test "returns {:error, :out_of_bounds} when length is zero", %{xml_text: xml_text} do
      assert {:error, :out_of_bounds} = XmlText.quote(xml_text, 0, 0)
    end

    test "returns {:error, :out_of_bounds} when length is negative", %{xml_text: xml_text} do
      assert {:error, :out_of_bounds} = XmlText.quote(xml_text, 0, -1)
    end

    test "returns {:error, :out_of_bounds} when index is out of bounds (negative)", %{
      xml_text: xml_text
    } do
      assert {:error, :out_of_bounds} = XmlText.quote(xml_text, -10, 1)
    end

    test "returns {:error, :out_of_bounds} when index + length exceeds text length", %{
      xml_text: xml_text
    } do
      assert {:error, :out_of_bounds} = XmlText.quote(xml_text, 0, 10)
    end
  end

  describe "node attributes" do
    setup do
      doc = Doc.with_options(%Doc.Options{client_id: 1})
      f = Doc.get_xml_fragment(doc, "xml")
      text = XmlFragment.push_and_get(f, XmlTextPrelim.from("hello"))
      %{doc: doc, xml_text: text, xml_fragment: f}
    end

    test "insert and get values of any type", %{xml_text: text} do
      for {key, value} <- [
            {"s", "v"},
            {"i", 1},
            {"f", 1.5},
            {"b", false},
            {"n", nil},
            {"l", [1, "a"]},
            {"m", %{"k" => "v"}}
          ] do
        assert :ok == XmlText.insert_attribute(text, key, value)
        assert value == XmlText.get_attribute(text, key)
      end

      assert nil == XmlText.get_attribute(text, "missing")
    end

    test "overwrite", %{xml_text: text} do
      XmlText.insert_attribute(text, "k", "a")
      XmlText.insert_attribute(text, "k", "b")
      assert %{"k" => "b"} == XmlText.get_attributes(text)
    end

    test "remove", %{xml_text: text} do
      XmlText.insert_attribute(text, "k", "a")
      XmlText.insert_attribute(text, "j", "b")
      assert :ok == XmlText.remove_attribute(text, "k")
      assert nil == XmlText.get_attribute(text, "k")
      assert %{"j" => "b"} == XmlText.get_attributes(text)
      assert :ok == XmlText.remove_attribute(text, "missing")
    end

    test "has_attribute?", %{xml_text: text} do
      XmlText.insert_attribute(text, "n", nil)
      assert XmlText.has_attribute?(text, "n")
      refute XmlText.has_attribute?(text, "missing")
      XmlText.remove_attribute(text, "n")
      refute XmlText.has_attribute?(text, "n")
    end

    test "node attributes are independent of formatting", %{xml_text: text} do
      XmlText.format(text, 0, 5, %{"bold" => true})
      XmlText.insert_attribute(text, "bold", "node")
      assert [%{insert: "hello", attributes: %{"bold" => true}}] == XmlText.to_delta(text)
      assert %{"bold" => "node"} == XmlText.get_attributes(text)
      assert "<bold>hello</bold>" == XmlText.to_string(text)
    end

    test "shared type value", %{xml_text: text} do
      XmlText.insert_attribute(text, "m", Yex.MapPrelim.from(%{"a" => 1}))
      assert %Yex.Map{} = map = XmlText.get_attribute(text, "m")
      assert %{"a" => 1} == Yex.Map.to_map(map)
    end

    test "XmlTextPrelim attributes are readable", %{xml_fragment: f} do
      t =
        XmlFragment.push_and_get(f, %XmlTextPrelim{
          delta: [%{insert: "x"}],
          attributes: %{"k" => "v"}
        })

      assert %{"k" => "v"} == XmlText.get_attributes(t)
    end

    test "sync over v1 and v2, concurrent writes converge", %{doc: doc, xml_text: text} do
      XmlText.insert_attribute(text, "k", "a")

      {:ok, v1} = Yex.encode_state_as_update_v1(doc)
      d1 = Doc.with_options(%Doc.Options{client_id: 2})
      :ok = Yex.apply_update_v1(d1, v1)
      t1 = XmlFragment.fetch!(Doc.get_xml_fragment(d1, "xml"), 0)
      assert "a" == XmlText.get_attribute(t1, "k")

      {:ok, v2} = Yex.encode_state_as_update_v2(doc)
      d2 = Doc.new()
      :ok = Yex.apply_update_v2(d2, v2)

      assert "a" ==
               XmlText.get_attribute(XmlFragment.fetch!(Doc.get_xml_fragment(d2, "xml"), 0), "k")

      XmlText.insert_attribute(text, "c", "from1")
      XmlText.insert_attribute(t1, "c", "from2")
      {:ok, u0} = Yex.encode_state_as_update_v1(doc)
      {:ok, u1} = Yex.encode_state_as_update_v1(d1)
      :ok = Yex.apply_update_v1(doc, u1)
      :ok = Yex.apply_update_v1(d1, u0)
      assert XmlText.get_attributes(text) == XmlText.get_attributes(t1)
    end

    test "inside a transaction", %{doc: doc, xml_text: text} do
      result =
        Doc.transaction(doc, fn ->
          XmlText.insert_attribute(text, "k", "v")
          XmlText.get_attributes(text)
        end)

      assert %{"k" => "v"} == result
    end

    test "deleted XmlText raises", %{xml_text: text, xml_fragment: f} do
      XmlFragment.delete(f, 0, 1)
      assert_raise Yex.DeletedSharedTypeError, fn -> XmlText.insert_attribute(text, "k", "v") end
      assert_raise Yex.DeletedSharedTypeError, fn -> XmlText.remove_attribute(text, "k") end
      assert_raise Yex.DeletedSharedTypeError, fn -> XmlText.get_attribute(text, "k") end
      assert_raise Yex.DeletedSharedTypeError, fn -> XmlText.get_attributes(text) end
    end

    test "undo", %{doc: doc, xml_text: text, xml_fragment: f} do
      {:ok, undo} = Yex.UndoManager.new(doc, f)
      XmlText.insert_attribute(text, "k", "v")
      :ok = Yex.UndoManager.undo(undo)
      assert %{} == XmlText.get_attributes(text)
    end

    test "as_prelim copies node attributes", %{xml_text: text, xml_fragment: f} do
      XmlText.insert_attribute(text, "k", "v")
      prelim = XmlText.as_prelim(text)
      assert %{"k" => "v"} == prelim.attributes
      copy = XmlFragment.push_and_get(f, prelim)
      assert %{"k" => "v"} == XmlText.get_attributes(copy)
      assert "hello" == XmlText.to_string(copy)
    end

    test "as_prelim with a shared-type attribute fails at insert", %{
      xml_text: text,
      xml_fragment: f
    } do
      XmlText.insert_attribute(text, "m", Yex.MapPrelim.from(%{"a" => 1}))
      prelim = XmlText.as_prelim(text)
      assert_raise ErlangError, fn -> XmlFragment.push(f, prelim) end
    end

    test "observe reports attribute changes in keys", %{doc: doc, xml_text: text} do
      ref = SharedType.observe(text)
      XmlText.insert_attribute(text, "k", "v")

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlTextEvent{
                        keys: %{"k" => %{action: :add, new_value: "v"}},
                        delta: []
                      }, _, _}

      XmlText.insert_attribute(text, "k", "w")

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlTextEvent{
                        keys: %{"k" => %{action: :update, old_value: "v", new_value: "w"}}
                      }, _, _}

      XmlText.remove_attribute(text, "k")

      assert_receive {:observe_event, ^ref,
                      %Yex.XmlTextEvent{keys: %{"k" => %{action: :delete, old_value: "w"}}}, _, _}

      Doc.transaction(doc, fn -> XmlText.insert(text, 0, "a") end)
      assert_receive {:observe_event, ^ref, %Yex.XmlTextEvent{keys: keys}, _, _}
      assert keys == %{}
    end

    test "observe_deep on the parent carries keys", %{xml_text: text, xml_fragment: f} do
      ref = SharedType.observe_deep(f)
      XmlText.insert_attribute(text, "k", "v")

      assert_receive {:observe_deep_event, ^ref,
                      [%Yex.XmlTextEvent{keys: %{"k" => %{action: :add, new_value: "v"}}}], _, _}
    end
  end
end
