# Benchmark for reads that convert document content into Elixir terms, plus the
# fixed cost of a call on a shared type.
#
#   MIX_ENV=dev mix run benchmark/read_conversions.exs

alias Yex.{Array, Doc, Map, Text}

setup = fn count ->
  doc = Doc.new()

  nested = Doc.get_map(doc, "nested")

  Enum.each(1..count, fn i ->
    Map.set(nested, "k#{i}", %{"a" => i, "b" => "str#{i}", "c" => [1, 2, 3]})
  end)

  flat = Doc.get_map(doc, "flat")
  Enum.each(1..count, fn i -> Map.set(flat, "k#{i}", "v#{i}") end)

  array = Doc.get_array(doc, "array")
  Array.insert_list(array, 0, Enum.to_list(1..count))

  text = Doc.get_text(doc, "text")
  Text.insert(text, 0, "hello")

  %{doc: doc, nested: nested, flat: flat, array: array, text: text}
end

# Calls the NIFs directly so the measurement is the conversion, not the dirty routing.
Benchee.run(
  %{
    "map_to_json nested" => fn %{nested: map} -> Yex.Nif.map_to_json(map, nil, nil) end,
    "map_to_map nested" => fn %{nested: map} -> Yex.Nif.map_to_map(map, nil) end,
    "map_to_json flat" => fn %{flat: map} -> Yex.Nif.map_to_json(map, nil, nil) end,
    "map_keys flat" => fn %{flat: map} -> Yex.Nif.map_keys(map, nil) end,
    "array_to_list" => fn %{array: array} -> Yex.Nif.array_to_list(array, nil) end,
    "array_length" => fn %{array: array} -> Yex.Nif.array_length(array, nil) end,
    "text_to_string" => fn %{text: text} -> Yex.Nif.text_to_string(text, nil) end,
    "doc_get_or_insert_array" => fn %{doc: doc} ->
      Yex.Nif.doc_get_or_insert_array(doc, nil, "array")
    end
  },
  inputs: %{"200 entries" => 200},
  # Runs in the benchmarking process, which then owns the doc.
  before_scenario: setup,
  time: 5,
  memory_time: 1
)
