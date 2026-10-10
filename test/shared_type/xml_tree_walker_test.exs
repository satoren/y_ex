defmodule YexXmlTreeWalkerTest do
  use ExUnit.Case, async: true

  alias Yex.{
    Doc,
    XmlFragment,
    XmlElement,
    XmlElementPrelim,
    XmlText,
    XmlTextPrelim,
    XmlFragmentPrelim
  }

  defmodule Worker do
    use GenServer

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_call({Yex.Doc, :run, fun}, _from, state), do: {:reply, fun.(), state}
  end

  defp label(%XmlElement{} = el), do: XmlElement.get_tag(el)
  defp label(%XmlText{} = text), do: XmlText.to_string(text)
  defp label(%XmlFragment{}), do: :fragment

  defp el(tag, children \\ [], attrs \\ %{}), do: XmlElementPrelim.new(tag, children, attrs)
  defp text(s), do: XmlTextPrelim.from(s)

  # <p>Hello <b>world</b></p>again, the tree from the yrs `successors` doc test.
  defp yrs_doc_tree, do: [el("p", [text("Hello "), el("b", [text("world")])]), text("again")]

  defp fill(mod, root, nodes), do: Enum.each(nodes, &mod.push(root, &1))

  defp root_in(doc, XmlFragment), do: Doc.get_xml_fragment(doc, "xml")
  defp root_in(doc, XmlElement), do: XmlFragment.fetch!(Doc.get_xml_fragment(doc, "xml"), 0)

  test "tree_walker raises on a deleted XmlElement root" do
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")
    root = XmlFragment.push_and_get(frag, el("root", [el("a")]))
    XmlFragment.delete(frag, 0, 1)
    assert_raise Yex.DeletedSharedTypeError, fn -> XmlElement.tree_walker(root) end
  end

  for kind <- [:fragment, :element] do
    describe "#{kind} root" do
      setup do
        doc = Doc.with_options(%Doc.Options{client_id: 1})
        frag = Doc.get_xml_fragment(doc, "xml")

        {mod, root} =
          case unquote(kind) do
            :fragment -> {XmlFragment, frag}
            :element -> {XmlElement, XmlFragment.push_and_get(frag, el("root"))}
          end

        %{doc: doc, frag: frag, mod: mod, root: root}
      end

      test "empty root returns an empty list", %{mod: mod, root: root} do
        assert [] == mod.tree_walker(root)
      end

      test "returns descendants in document order, root excluded", %{mod: mod, root: root} do
        fill(mod, root, yrs_doc_tree())
        assert ["p", "Hello ", "b", "world", "again"] == Enum.map(mod.tree_walker(root), &label/1)
      end

      test "walks deep nesting in pre-order", %{mod: mod, root: root} do
        fill(mod, root, [
          el("a", [
            el("b", [el("c", [el("d", [el("e"), text("t1")]), text("t2")]), el("f")]),
            el("g")
          ]),
          el("h")
        ])

        assert ~w(a b c d e t1 t2 f g h) == Enum.map(mod.tree_walker(root), &label/1)
      end

      test "yields a nested fragment and then its children", %{mod: mod, root: root} do
        fill(mod, root, [XmlFragmentPrelim.new([el("x"), text("y")]), el("z")])
        assert [:fragment, "x", "y", "z"] == Enum.map(mod.tree_walker(root), &label/1)
      end

      test "does not descend into XmlText", %{mod: mod, root: root} do
        mod.push(root, text("a"))
        [t] = mod.tree_walker(root)
        XmlText.insert(t, 1, "b", %{"bold" => true})
        assert [%XmlText{}] = mod.tree_walker(root)
      end

      test "skips deleted subtrees and continues", %{mod: mod, root: root} do
        fill(mod, root, [el("a"), el("b", [el("c"), text("d")]), el("e")])
        mod.delete(root, 1, 1)
        assert ["a", "e"] == Enum.map(mod.tree_walker(root), &label/1)
      end

      test "filter selects without pruning", %{mod: mod, root: root} do
        fill(mod, root, [el("skip", [el("keep"), text("t")]), text("u")])

        assert ["skip", "keep"] ==
                 Enum.map(mod.tree_walker(root, &match?(%XmlElement{}, &1)), &label/1)

        assert ["keep"] ==
                 root
                 |> mod.tree_walker(&match?(%XmlElement{}, &1))
                 |> Enum.filter(&(XmlElement.get_tag(&1) == "keep"))
                 |> Enum.map(&label/1)

        assert ["keep"] ==
                 Enum.map(
                   mod.tree_walker(root, fn
                     %XmlElement{} = e -> XmlElement.get_tag(e) == "keep"
                     _ -> false
                   end),
                   &label/1
                 )
      end

      test "filter calling NIFs runs in another worker process", %{mod: mod} do
        {:ok, worker} = GenServer.start_link(Worker, nil)
        doc = Doc.new(worker)
        frag = Doc.get_xml_fragment(doc, "xml")

        root =
          if mod == XmlFragment, do: frag, else: XmlFragment.push_and_get(frag, el("root"))

        fill(mod, root, yrs_doc_tree())

        assert ["b"] ==
                 Enum.map(
                   mod.tree_walker(root, &(match?(%XmlElement{}, &1) and label(&1) == "b")),
                   &label/1
                 )
      end

      test "a raising filter reraises in the caller and leaves the worker alive", %{mod: mod} do
        {:ok, worker} = GenServer.start_link(Worker, nil)
        doc = Doc.new(worker)
        frag = Doc.get_xml_fragment(doc, "xml")

        root =
          if mod == XmlFragment, do: frag, else: XmlFragment.push_and_get(frag, el("root"))

        fill(mod, root, [el("a")])

        assert_raise RuntimeError, "boom", fn ->
          mod.tree_walker(root, fn _ -> raise "boom" end)
        end

        assert Process.alive?(worker)
        assert ["a"] == Enum.map(mod.tree_walker(root), &label/1)
      end

      test "joins an open transaction and sees its inserts", %{doc: doc, mod: mod, root: root} do
        result =
          Doc.transaction(doc, fn ->
            fill(mod, root, [el("a", [text("b")])])
            Enum.map(mod.tree_walker(root), &label/1)
          end)

        assert ["a", "b"] == result
      end

      test "a remote tree walks the same after v1 and v2 updates", %{
        doc: doc,
        mod: mod,
        root: root
      } do
        fill(mod, root, yrs_doc_tree())
        expected = Enum.map(mod.tree_walker(root), &label/1)

        {:ok, v1} = Yex.encode_state_as_update_v1(doc)
        d1 = Doc.new()
        :ok = Yex.apply_update_v1(d1, v1)
        assert expected == Enum.map(mod.tree_walker(root_in(d1, mod)), &label/1)

        {:ok, v2} = Yex.encode_state_as_update_v2(doc)
        d2 = Doc.new()
        :ok = Yex.apply_update_v2(d2, v2)
        assert expected == Enum.map(mod.tree_walker(root_in(d2, mod)), &label/1)
      end

      test "returned nodes are live handles", %{mod: mod, root: root} do
        fill(mod, root, [el("a")])
        [a] = mod.tree_walker(root)
        XmlElement.push(a, text("x"))
        assert mod.to_string(root) =~ "<a>x</a>"
      end

      test "query_selector returns the first match in document order", %{mod: mod, root: root} do
        fill(mod, root, [
          el("x", [el("y", [el("hit", [], %{"n" => "1"})])]),
          el("hit", [], %{"n" => "2"})
        ])

        assert %XmlElement{} = found = mod.query_selector(root, "hit")
        assert "1" == XmlElement.get_attribute(found, "n")
      end

      test "query_selector matches tags case-insensitively", %{mod: mod, root: root} do
        fill(mod, root, [el("div"), el("SPAN")])
        assert "div" == label(mod.query_selector(root, "DIV"))
        assert "SPAN" == label(mod.query_selector(root, "span"))
      end

      test "query_selector never returns text or the root", %{mod: mod, root: root} do
        fill(mod, root, [text("root"), text("div")])
        assert nil == mod.query_selector(root, "root")
        assert nil == mod.query_selector(root, "div")
        assert [] == mod.query_selector_all(root, "root")
      end

      test "no match returns nil and []", %{mod: mod, root: root} do
        fill(mod, root, [el("a")])
        assert nil == mod.query_selector(root, "b")
        assert [] == mod.query_selector_all(root, "b")
      end

      test "query_selector_all returns all matches in order, nested included", %{
        mod: mod,
        root: root
      } do
        fill(mod, root, [
          el("li", [], %{"n" => "1"}),
          el("ul", [el("li", [el("li", [], %{"n" => "3"})], %{"n" => "2"})]),
          el("li", [], %{"n" => "4"})
        ])

        assert ~w(1 2 3 4) ==
                 Enum.map(mod.query_selector_all(root, "LI"), &XmlElement.get_attribute(&1, "n"))
      end

      test "Yex.Xml attribute readers work on walker output", %{mod: mod, root: root} do
        fill(mod, root, [
          el("a", [], %{"id" => "e"}),
          %XmlTextPrelim{delta: [%{insert: "t"}], attributes: %{"id" => "t"}}
        ])

        assert [%{"id" => "e"}, %{"id" => "t"}] ==
                 Enum.map(mod.tree_walker(root), &Yex.Xml.get_attributes/1)

        assert ["e", "t"] == Enum.map(mod.tree_walker(root), &Yex.Xml.get_attribute(&1, "id"))
      end
    end
  end
end
