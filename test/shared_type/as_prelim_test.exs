defmodule Yex.AsPrelimTest do
  use ExUnit.Case, async: true

  alias Yex.{
    Array,
    ArrayPrelim,
    Doc,
    MapPrelim,
    Text,
    TextPrelim,
    XmlElement,
    XmlElementPrelim,
    XmlFragment,
    XmlText,
    XmlTextPrelim
  }

  alias Yex.Map, as: YMap

  # as_prelim/1 builds the whole tree in one NIF call. Yex.ReferencePrelim is the Elixir
  # implementation it replaced; every shared type here must convert exactly as it did.

  setup do
    doc = Doc.with_options(%Doc.Options{client_id: 1})
    map = Doc.get_map(doc, "map")

    YMap.set(map, "plain", %{
      "n" => 1,
      "list" => [1, "two", %{"deep" => [true, nil]}],
      "buffer" => %Yex.Buffer{data: <<0, 255>>}
    })

    YMap.set(map, "big", 9_007_199_254_740_993)
    YMap.set(map, "gone", "x")
    YMap.delete(map, "gone")

    nested =
      YMap.set_and_get(
        map,
        "nested",
        MapPrelim.from(%{
          "array" =>
            ArrayPrelim.from([1, MapPrelim.from(%{"x" => "y"}), TextPrelim.from("inner")])
        })
      )

    text = YMap.set_and_get(map, "text", TextPrelim.from("hello world"))
    Text.format(text, 1, 3, %{"bold" => true, "link" => %{"href" => "x"}})
    Text.insert_embed(text, 5, %{"kind" => "mention"})
    Text.insert_embed(text, 0, MapPrelim.from(%{"embedded" => 1}), %{"italic" => true})
    YMap.set(map, "link", YMap.link(map, "plain"))
    YMap.set(map, "subdoc", Doc.new())

    array = Doc.get_array(doc, "array")
    Array.insert_list(array, 0, [1, "a", %{"k" => [1]}])
    Array.push(array, ArrayPrelim.from([TextPrelim.from("t"), ArrayPrelim.from([])]))
    Array.push(array, XmlElementPrelim.new("in-array", [XmlTextPrelim.from("x")]))
    Array.delete(array, 1)

    frag = Doc.get_xml_fragment(doc, "xml")

    element =
      XmlFragment.push_and_get(
        frag,
        XmlElementPrelim.new(
          "div",
          [
            XmlTextPrelim.from("text"),
            XmlElementPrelim.new("span", [XmlElementPrelim.empty("b")], %{"a" => "1"}),
            XmlElementPrelim.empty("removed")
          ],
          %{"class" => "c"}
        )
      )

    XmlElement.insert_attribute(element, "map", MapPrelim.from(%{"a" => "b"}))
    XmlElement.delete(element, 2, 1)

    xml_text = XmlFragment.push_and_get(frag, XmlTextPrelim.from("formatted text"))
    XmlText.format(xml_text, 0, 4, %{"bold" => true})
    XmlText.insert_attribute(xml_text, "plain", "v")
    XmlText.insert_attribute(xml_text, "array", ArrayPrelim.from([1, 2]))

    %{
      doc: doc,
      types: [map, nested, text, array, frag, element, xml_text]
    }
  end

  test "matches the Elixir implementation for every shared type", %{types: types} do
    for type <- types do
      assert normalize(Yex.Output.as_prelim(type)) ==
               normalize(Yex.ReferencePrelim.as_prelim(type))
    end
  end

  test "matches inside a transaction", %{doc: doc, types: types} do
    Doc.transaction(doc, fn ->
      for type <- types do
        assert normalize(Yex.Output.as_prelim(type)) ==
                 normalize(Yex.ReferencePrelim.as_prelim(type))
      end
    end)
  end

  test "the DirtyCpu twin builds the same prelim", %{types: types} do
    for type <- types do
      assert normalize(Yex.Nif.shared_type_as_prelim_dirty(type, nil)) ==
               normalize(Yex.Output.as_prelim(type))
    end
  end

  test "stops at a non-XML child like children/1" do
    # A fragment holding <a>x</a>, a Y.Map and <b></b>, written by yjs (see
    # xml_fragment_test.exs).
    update = Base.decode64!("AQYBAAcBA3htbAMBYYcBAAGHAQEDAWIoAAEBAWsBdwF2BwABAAYEAAEEAXgA")
    doc = Doc.new()
    :ok = Yex.apply_update_v1(doc, update)
    frag = Doc.get_xml_fragment(doc, "xml")

    assert %Yex.XmlFragmentPrelim{children: [%XmlElementPrelim{tag: "a"}]} =
             prelim = XmlFragment.as_prelim(frag)

    assert normalize(prelim) == normalize(Yex.ReferencePrelim.as_prelim(frag))
  end

  test "a deleted shared type raises as before", %{doc: doc} do
    map = Doc.get_map(doc, "map")
    {:ok, nested} = YMap.fetch(map, "nested")
    YMap.delete(map, "nested")

    assert_raise Yex.DeletedSharedTypeError, fn -> YMap.as_prelim(nested) end
    assert_raise Yex.DeletedSharedTypeError, fn -> Yex.ReferencePrelim.as_prelim(nested) end
  end

  test "the normal NIF converts within its budget and declines past it" do
    doc = Doc.new()
    array = Doc.get_array(doc, "array")
    Array.insert_list(array, 0, [1, 2, 3])

    # The array and its three values.
    assert %ArrayPrelim{list: [1.0, 2.0, 3.0]} = Yex.Nif.shared_type_as_prelim(array, nil, 4)
    assert :dirty == Yex.Nif.shared_type_as_prelim(array, nil, 3)
  end

  test "a tree over the budget converts through the DirtyCpu twin" do
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")

    Doc.transaction(doc, fn ->
      for i <- 1..(Yex.Nif.dirty_prelim_values() + 1) do
        XmlFragment.push(frag, XmlElementPrelim.new("p", [XmlTextPrelim.from("#{i}")]))
      end
    end)

    assert :dirty == Yex.Nif.shared_type_as_prelim(frag, nil, Yex.Nif.dirty_prelim_values())

    assert normalize(XmlFragment.as_prelim(frag)) ==
             normalize(Yex.ReferencePrelim.as_prelim(frag))
  end

  test "a deeply nested type converts on a dirty scheduler" do
    doc = Doc.new()
    root = Doc.get_map(doc, "map")

    # Dirty CPU schedulers have small stacks, and the conversion recurses once per level.
    _ =
      Enum.reduce(1..400, root, fn _, parent ->
        YMap.set_and_get(parent, "child", MapPrelim.from(%{"leaf" => "v"}))
      end)

    assert %MapPrelim{map: %{"child" => %MapPrelim{}}} =
             Yex.Nif.shared_type_as_prelim_dirty(root, nil)
  end

  # A WeakPrelim holds a resource made fresh by every conversion, so two conversions of
  # the same link are equal in kind only.
  defp normalize(%Yex.WeakPrelim{}), do: :weak_prelim
  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(%module{} = struct), do: {module, normalize(Map.from_struct(struct))}

  defp normalize(%{} = map) do
    Map.new(map, fn {key, value} -> {key, normalize(value)} end)
  end

  defp normalize(value), do: value
end
