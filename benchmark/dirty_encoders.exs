# Benchmark for Yex.Nif.dirty_encode_items/0 and Yex.Nif.dirty_json_items/0.
# The encoders and to_json readers cost what the document costs, so this compares each
# on normal vs DirtyCpu schedulers across doc sizes, measures what the item-count check
# adds to a small call, then measures how long a large call blocks a neighbour on the
# same scheduler.
# Limits: largest power of two below the smallest item count whose normal median exceeds 1 ms.
# Run with: MIX_ENV=dev mix run benchmark/dirty_encoders.exs

alias Yex.Doc

# Map entries are the most expensive shape per item; one map entry is one item.
map_doc = fn n ->
  doc = Doc.new()
  map = Doc.get_map(doc, "m")
  Doc.transaction(doc, fn -> for i <- 1..n, do: Yex.Map.set(map, "k#{i}", i) end)
  %{doc: doc, map: map}
end

# One insert of n elements is n items. Pushing one by one is quadratic to set up.
array_doc = fn n ->
  doc = Doc.new()
  array = Doc.get_array(doc, "a")
  Yex.Array.insert_list(array, 0, Enum.to_list(1..n))
  %{doc: doc, array: array}
end

inputs =
  for n <- [10, 100, 500, 1_000, 2_000, 10_000, 20_000, 40_000, 200_000] do
    {"#{n} items", Map.merge(map_doc.(n), array_doc.(n) |> Map.take([:array]))}
  end

# Remote state vector of an empty doc, so the diff is the whole document.
empty_sv = <<0>>
empty_sv_payload = <<1, 0>>

# `limit` nil: never decline, so the normal NIF always does the work.
calls = %{
  "encode_state_as_update_v1" => {
    fn %{doc: d}, limit -> Yex.Nif.encode_state_as_update_v1(d, nil, nil, limit) end,
    fn %{doc: d} -> Yex.Nif.encode_state_as_update_v1_dirty(d, nil, nil) end
  },
  "encode_state_as_update_v2" => {
    fn %{doc: d}, limit -> Yex.Nif.encode_state_as_update_v2(d, nil, nil, limit) end,
    fn %{doc: d} -> Yex.Nif.encode_state_as_update_v2_dirty(d, nil, nil) end
  },
  "encode_diff_and_state_vector_v1" => {
    fn %{doc: d}, limit -> Yex.Nif.encode_diff_and_state_vector_v1(d, nil, empty_sv, limit) end,
    fn %{doc: d} -> Yex.Nif.encode_diff_and_state_vector_v1_dirty(d, nil, empty_sv) end
  },
  "encode_sync_step1_response_v1" => {
    fn %{doc: d}, limit ->
      Yex.Nif.encode_sync_step1_response_v1(d, nil, empty_sv_payload, nil, limit)
    end,
    fn %{doc: d} -> Yex.Nif.encode_sync_step1_response_v1_dirty(d, nil, empty_sv_payload, nil) end
  },
  "map_to_json" => {
    fn %{map: m}, limit -> Yex.Nif.map_to_json(m, nil, limit) end,
    fn %{map: m} -> Yex.Nif.map_to_json_dirty(m, nil) end
  },
  "array_to_json" => {
    fn %{array: a}, limit -> Yex.Nif.array_to_json(a, nil, limit) end,
    fn %{array: a} -> Yex.Nif.array_to_json_dirty(a, nil) end
  }
}

bench = fn jobs, inputs ->
  Benchee.run(jobs,
    inputs: inputs,
    # Free each call's result outside the timed call.
    after_each: fn _ ->
      :erlang.garbage_collect()
      :erlang.yield()
    end,
    warmup: 1,
    time: 2
  )
end

for {name, {normal, dirty}} <- Enum.sort(calls) do
  IO.puts("\n=== #{name}: normal vs DirtyCpu scheduler (NIF direct) ===\n")
  bench.(%{"normal" => &normal.(&1, nil), "dirty" => dirty}, inputs)
end

IO.puts("\n=== cost of the item-count check on small docs ===\n")
{normal, _} = calls["encode_state_as_update_v1"]

bench.(
  %{
    "encode_state_as_update_v1, no limit" => &normal.(&1, nil),
    "encode_state_as_update_v1, limit checked" => &normal.(&1, Yex.Nif.dirty_encode_items())
  },
  Enum.take(inputs, 3)
)

IO.puts("\n=== neighbour wake-up gap during a call on a 200_000 item doc ===\n")

{_, large} = List.last(inputs)

measure = fn fun ->
  parent = self()

  ticker =
    :erlang.spawn_opt(
      fn ->
        tick = fn tick, worst, last ->
          receive do
            :stop ->
              now = System.monotonic_time(:millisecond)
              send(parent, {:worst_gap_ms, max(worst, now - last)})
          after
            10 ->
              now = System.monotonic_time(:millisecond)
              tick.(tick, max(worst, now - last), now)
          end
        end

        tick.(tick, 0, System.monotonic_time(:millisecond))
      end,
      [{:scheduler, :erlang.system_info(:scheduler_id)}]
    )

  Process.sleep(200)
  {us, _} = :timer.tc(fun)
  send(ticker, :stop)
  receive do: ({:worst_gap_ms, gap} -> {div(us, 1000), gap})
end

run_pinned = fn fun ->
  parent = self()
  :erlang.spawn_opt(fn -> send(parent, {:result, measure.(fun)}) end, [{:scheduler, 1}])
  receive do: ({:result, result} -> result)
end

for {name, {normal, dirty}} <- Enum.sort(calls),
    {label, fun} <- [{name, &normal.(&1, nil)}, {"#{name}_dirty", dirty}] do
  results = for _ <- 1..3, do: run_pinned.(fn -> fun.(large) end)

  IO.puts(
    "#{label}: call #{Enum.map_join(results, " / ", &elem(&1, 0))} ms, " <>
      "worst neighbour gap #{Enum.map_join(results, " / ", &elem(&1, 1))} ms (asked for 10)"
  )
end
