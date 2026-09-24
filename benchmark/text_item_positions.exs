alias Yex.{Doc, StickyIndex, XmlFragment, XmlTextPrelim}
doc = Doc.with_options(%Doc.Options{offset_kind: :utf16})
root = Doc.get_xml_fragment(doc, "default")
:ok = XmlFragment.push(root, XmlTextPrelim.from(String.duplicate("x", 131_072)))
leaf = XmlFragment.fetch!(root, 0)
json = StickyIndex.new(leaf, 0, :after) |> StickyIndex.to_json()
identity = if Code.ensure_loaded?(Jason), do: Jason.decode!(json), else: :json.decode(json)
%{"item" => %{"client" => client, "clock" => clock}} = identity

{microseconds, {:ok, [positions]}} =
  :timer.tc(fn ->
    StickyIndex.resolve_text_items(leaf, [%{client: client, clock: clock, count: 131_072}])
  end)

131_072 = length(positions)

true =
  Enum.with_index(positions)
  |> Enum.all?(fn {position, index} -> position == %{status: :live, index: index} end)

IO.puts("PASS batch units=131072 runs=1 milliseconds=#{div(microseconds, 1000)}")
