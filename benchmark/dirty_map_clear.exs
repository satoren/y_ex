# Benchmark for Yex.Nif.dirty_clear_items/0.
# map_clear costs what the cleared content costs, plus one observer event entry per
# removed key. This times the normal NIF (no limit) on fresh maps of several shapes, with
# and without observe/observe_deep attached, and prints the median per doc item count.
# Limit: largest power of two below the smallest item count whose median exceeds 1 ms.
# Run with: MIX_ENV=dev mix run benchmark/dirty_map_clear.exs

alias Yex.Doc

# Each shape's doc items per map entry: flat 1, nested map with one key 2, nested map
# with eight keys 9.
shapes = %{
  flat: {1, & &1},
  nested: {2, &Yex.MapPrelim.from(%{"k" => &1})},
  wide: {9, fn _ -> Yex.MapPrelim.from(Map.new(1..8, &{"k#{&1}", &1})) end}
}

build = fn n, value, observed ->
  doc = Doc.new()
  map = Doc.get_map(doc, "m")
  Doc.transaction(doc, fn -> for i <- 1..n, do: Yex.Map.set(map, "k#{i}", value.(i)) end)
  {:ok, _} = Doc.monitor_update(doc)

  if observed do
    Yex.SharedType.observe(map)
    Yex.SharedType.observe_deep(map)
  end

  map
end

median_us = fn n, value, observed ->
  times =
    for _ <- 1..15 do
      map = build.(n, value, observed)
      {us, :ok} = :timer.tc(fn -> Yex.Nif.map_clear(map, nil, nil) end)
      :erlang.garbage_collect()
      us
    end

  times |> Enum.sort() |> Enum.at(7)
end

for observed <- [false, true],
    {name, {per_entry, value}} <- Enum.sort(shapes),
    items <- [256, 512, 1_024, 2_048, 4_096] do
  n = div(items, per_entry)
  IO.puts("observed=#{observed} #{name} items=#{n * per_entry}: #{median_us.(n, value, observed)} us")
end
