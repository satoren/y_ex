# Benchmark for converting nested values between Elixir terms and yrs: inserting lists
# of maps, reading them back, text deltas and observer events.
#
#   MIX_ENV=dev mix run benchmark/term_building.exs

alias Yex.{Array, Doc, Map, Text}

flush = fn flush ->
  receive do
    _ -> flush.(flush)
  after
    0 -> :ok
  end
end

setup = fn count ->
  doc = Doc.new()

  array = Doc.get_array(doc, "array")

  Array.insert_list(
    array,
    0,
    Enum.map(1..count, fn i -> %{"id" => i, "name" => "item#{i}", "tags" => ["a", "b"]} end)
  )

  text = Doc.get_text(doc, "text")

  Enum.each(0..(count - 1), fn i ->
    Text.insert(
      text,
      i * 6,
      "word#{rem(i, 10)} ",
      if(rem(i, 2) == 0, do: %{"bold" => true}, else: %{})
    )
  end)

  observed = Doc.new()
  observed_array = Doc.get_array(observed, "array")
  observed_map = Doc.get_map(observed, "map")
  Yex.SharedType.observe(observed_array)
  Yex.SharedType.observe(observed_map)

  payload =
    Enum.map(1..count, fn i ->
      %{"id" => i, "name" => "n#{i}", "nested" => %{"x" => [1, 2, 3]}}
    end)

  %{
    array: array,
    text: text,
    observed_array: observed_array,
    observed_map: observed_map,
    payload: payload,
    count: count
  }
end

# Runs in the benchmarking process, which then owns the docs. No memory_time: Benchee
# measures memory in another process, which would have to call into the worker.
Benchee.run(
  %{
    "Array.insert_list + delete_range" => fn %{array: array, payload: payload, count: count} ->
      Array.insert_list(array, count, payload)
      Array.delete_range(array, count, count)
    end,
    "Array.to_list" => fn %{array: array} -> Array.to_list(array) end,
    "Array.to_json" => fn %{array: array} -> Array.to_json(array) end,
    "Text.to_delta" => fn %{text: text} -> Text.to_delta(text) end,
    "observed Array.push" => fn %{observed_array: array} ->
      Array.push(array, %{"k" => "v"})
      flush.(flush)
    end,
    "observed Map.set" => fn %{observed_map: map} ->
      Map.set(map, "key", "value")
      flush.(flush)
    end
  },
  inputs: %{"100 items" => 100},
  before_scenario: setup,
  time: 5
)
