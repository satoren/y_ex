alias Yex.{Doc,Text}

Benchee.run(%{
  "text format"  => fn %{text: text, text_data: data} -> Text.format(text, 0, 10, %{ "href" => "http://github.com" }) end,
},
before_scenario: fn  ->
  doc = Yex.Doc.new()
  text = Doc.get_text(doc, "text")
  Text.insert(text, 0, "12345678901")
  %{text: text}
end,
  memory_time: 5
)
