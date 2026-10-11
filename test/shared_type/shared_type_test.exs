defmodule Yex.SharedTypeTest do
  use ExUnit.Case, async: true
  alias Yex.{SharedType, Doc, Text, Output}

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    {:ok, doc: doc, text: text}
  end

  describe "observe/2" do
    test "basic observation", %{text: text} do
      ref = SharedType.observe(text, [])
      assert is_reference(ref)
    end

    test "observation with default options", %{text: text} do
      ref = SharedType.observe(text)
      assert is_reference(ref)
    end

    test "observation with metadata", %{doc: doc, text: text} do
      metadata = %{test: "metadata"}
      ref = SharedType.observe(text, metadata: metadata)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      assert_receive {:observe_event, ^ref, _event, _origin, ^metadata}
    end

    test "unobserve stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe(text, [])
      :ok = SharedType.unobserve(ref)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      refute_receive {:observe_event, ^ref, _event, _origin, _metadata}, 10
    end

    test "unobserve inside a transaction stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe(text, [])

      Doc.transaction(doc, fn ->
        :ok = SharedType.unobserve(ref)
        Text.insert(text, 0, "hello")
      end)

      Text.insert(text, 0, "world")

      refute_receive {:observe_event, ^ref, _event, _origin, _metadata}, 10
    end

    test "observe inside a transaction joins it and receives later events", %{
      doc: doc,
      text: text
    } do
      ref = Doc.transaction(doc, fn -> SharedType.observe(text, metadata: :m) end)

      Text.insert(text, 0, "hello")

      assert_receive {:observe_event, ^ref, %Yex.TextEvent{delta: [%{insert: "hello"}]}, nil, :m}

      Doc.transaction(doc, fn -> :ok = SharedType.unobserve(ref) end)
      Text.insert(text, 0, "world")
      refute_receive {:observe_event, ^ref, _event, _origin, _metadata}, 10
    end

    test "observe inside a transaction receives changes made in that transaction", %{
      doc: doc,
      text: text
    } do
      ref =
        Doc.transaction(doc, fn ->
          Text.insert(text, 0, "a")
          ref = SharedType.observe(text)
          Text.insert(text, 1, "b")
          ref
        end)

      assert_receive {:observe_event, ^ref, %Yex.TextEvent{delta: [%{insert: "ab"}]}, nil, _}
      refute_receive {:observe_event, ^ref, _event, _origin, _metadata}, 10
    end

    test "observe inside a transaction works for every shared type", %{doc: doc} do
      map = Doc.get_map(doc, "map")
      array = Doc.get_array(doc, "array")
      fragment = Doc.get_xml_fragment(doc, "xml")
      element = Yex.XmlFragment.insert_and_get(fragment, 0, Yex.XmlElementPrelim.empty("div"))
      xml_text = Yex.XmlFragment.insert_and_get(fragment, 1, Yex.XmlTextPrelim.from(""))

      refs =
        Doc.transaction(doc, fn ->
          for type <- [map, array, fragment, element, xml_text] do
            SharedType.observe(type)
          end
        end)

      [map_ref, array_ref, fragment_ref, element_ref, xml_text_ref] = refs

      Yex.Map.set(map, "k", "v")
      assert_receive {:observe_event, ^map_ref, %Yex.MapEvent{}, _, _}

      Yex.Array.push(array, 1)
      assert_receive {:observe_event, ^array_ref, %Yex.ArrayEvent{}, _, _}

      Yex.XmlElement.insert_attribute(element, "class", "x")
      assert_receive {:observe_event, ^element_ref, %Yex.XmlEvent{}, _, _}

      Yex.XmlText.insert(xml_text, 0, "hi")
      assert_receive {:observe_event, ^xml_text_ref, %Yex.XmlTextEvent{}, _, _}

      Yex.XmlFragment.push(fragment, Yex.XmlTextPrelim.from(""))
      assert_receive {:observe_event, ^fragment_ref, %Yex.XmlEvent{}, _, _}
    end

    test "unobserve after the observed type was deleted", %{doc: doc} do
      map = Doc.get_map(doc, "map")
      nested = Yex.Map.set_and_get(map, "nested", Yex.TextPrelim.from(""))
      ref = SharedType.observe(nested, [])

      :ok = Yex.Map.delete(map, "nested")

      assert :ok = SharedType.unobserve(ref)
    end
  end

  describe "observe_deep/2" do
    test "deep observation with default options", %{text: text} do
      ref = SharedType.observe_deep(text)
      assert is_reference(ref)
    end

    test "deep observation with metadata", %{doc: doc, text: text} do
      metadata = %{test: "deep_metadata"}
      ref = SharedType.observe_deep(text, metadata: metadata)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      assert_receive {:observe_deep_event, ^ref, _events, _origin, ^metadata}
    end

    test "unobserve_deep stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe_deep(text, [])
      :ok = SharedType.unobserve_deep(ref)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      refute_receive {:observe_deep_event, ^ref, _events, _origin, _metadata}, 10
    end

    test "unobserve_deep inside a transaction stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe_deep(text, [])

      Doc.transaction(doc, fn ->
        :ok = SharedType.unobserve_deep(ref)
        Text.insert(text, 0, "hello")
      end)

      refute_receive {:observe_deep_event, ^ref, _events, _origin, _metadata}, 10
    end

    test "observe_deep inside a transaction joins it and receives later events", %{
      doc: doc,
      text: text
    } do
      ref = Doc.transaction(doc, fn -> SharedType.observe_deep(text, metadata: :m) end)

      Text.insert(text, 0, "hello")

      assert_receive {:observe_deep_event, ^ref, [%Yex.TextEvent{delta: [%{insert: "hello"}]}],
                      nil, :m}

      Doc.transaction(doc, fn -> :ok = SharedType.unobserve_deep(ref) end)
      Text.insert(text, 0, "world")
      refute_receive {:observe_deep_event, ^ref, _events, _origin, _metadata}, 10
    end

    test "observe_deep inside a transaction works for every shared type", %{doc: doc} do
      map = Doc.get_map(doc, "map")
      array = Doc.get_array(doc, "array")
      fragment = Doc.get_xml_fragment(doc, "xml")

      [map_ref, array_ref, fragment_ref] =
        Doc.transaction(doc, fn ->
          for type <- [map, array, fragment], do: SharedType.observe_deep(type)
        end)

      Yex.Map.set(map, "k", "v")
      assert_receive {:observe_deep_event, ^map_ref, [%Yex.MapEvent{}], _, _}

      Yex.Array.push(array, 1)
      assert_receive {:observe_deep_event, ^array_ref, [%Yex.ArrayEvent{}], _, _}

      Yex.XmlFragment.push(fragment, Yex.XmlTextPrelim.from(""))
      assert_receive {:observe_deep_event, ^fragment_ref, [%Yex.XmlEvent{}], _, _}
    end
  end

  describe "Output protocol" do
    test "as_prelim returns a TextPrelim for Text", %{text: text} do
      assert %Yex.TextPrelim{} = Output.as_prelim(text)
    end
  end
end
