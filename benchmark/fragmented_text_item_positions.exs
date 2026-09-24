alias Yex.{Doc, StickyIndex, XmlFragment, XmlText, XmlTextPrelim}
doc = Doc.with_options(%Doc.Options{offset_kind: :utf16})
root = Doc.get_xml_fragment(doc, "default")
:ok = XmlFragment.push(root, XmlTextPrelim.from(String.duplicate("x", 131_072)))
leaf = XmlFragment.fetch!(root, 0)
json = StickyIndex.new(leaf, 0, :after) |> StickyIndex.to_json()
identity = if Code.ensure_loaded?(Jason), do: Jason.decode!(json), else: :json.decode(json)
%{"item" => %{"client" => client, "clock" => clock}} = identity

Doc.transaction(doc, fn ->
  for index <- 0..131_040//32, do: XmlText.format(leaf, index, 16, %{"bold" => true})
end)

{microseconds, {:ok, [positions]}} =
  :timer.tc(fn ->
    StickyIndex.resolve_text_items(leaf, [%{client: client, clock: clock, count: 131_072}])
  end)

131_072 = length(positions)

true =
  Enum.with_index(positions)
  |> Enum.all?(fn {position, index} -> position == %{status: :live, index: index} end)

IO.puts(
  "PASS fragmented batch units=131072 formatting_runs=4096 milliseconds=#{div(microseconds, 1000)}"
)
