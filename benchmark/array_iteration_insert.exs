# Benchmark for array insertion strategies with iterative ranges.
#
#   MIX_ENV=dev mix run benchmark/array_iteration_insert.exs

alias Yex.{Array, Doc}

Benchee.run(
  %{
    "Array.insert_list/3 (Enum.to_list(1..n))" => fn count ->
      doc = Doc.new()
      array = Doc.get_array(doc, "array")
      Array.insert_list(array, 0, Enum.to_list(1..count))
    end,
    "Array.push/2 (Enum.each 1..n)" => fn count ->
      doc = Doc.new()
      array = Doc.get_array(doc, "array")

      Enum.each(1..count, fn value ->
        Array.push(array, value)
      end)
    end,
  },
  inputs: %{
    "1..10" => 10,
    "1..100" => 100,
    "1..1000" => 1000
  }
)
