alias Yex.{Doc,Text}

Benchee.run(%{
  "insert text"  => fn %{text: text, text_data: data} -> Text.insert(text, 0, data) end,
},
inputs: %{"large text" => String.duplicate("1", 1000 * 10), "small text" => String.duplicate("1", 10)},
before_scenario: fn data ->
  doc = Yex.Doc.new()
  text = Doc.get_text(doc, "text")
  %{text: text, text_data: data}
end,
  memory_time: 5
)
