# Benchmark for choosing Yex.Nif.dirty_cutoff/0.
# Compares apply_update on normal vs DirtyCpu schedulers across update sizes,
# then measures how long a large apply blocks a neighbour on the same scheduler.
# Cutoff: largest power of two below the smallest map input whose normal median exceeds 1 ms.
# Run with: MIX_ENV=dev mix run benchmark/dirty_cutoff.exs

alias Yex.{Doc, Text}

build = fn insert_fn ->
  src = Doc.new()
  insert_fn.(src)
  {:ok, v1} = Yex.encode_state_as_update_v1(src)
  {:ok, v2} = Yex.encode_state_as_update_v2(src)
  %{v1: v1, v2: v2}
end

map_entries = fn n ->
  fn doc ->
    map = Doc.get_map(doc, "m")
    Doc.transaction(doc, fn -> for i <- 1..n, do: Yex.Map.set(map, "k#{i}", i) end)
  end
end

text_insert = fn n ->
  fn doc -> Text.insert(Doc.get_text(doc, "t"), 0, String.duplicate("x", n)) end
end

small_edits = fn n ->
  fn doc ->
    text = Doc.get_text(doc, "t")
    :rand.seed(:exsss, {1, 2, 3})

    Doc.transaction(doc, fn ->
      for len <- 0..(n - 1), do: Text.insert(text, :rand.uniform(len + 1) - 1, "x")
    end)
  end
end

map_inputs =
  for n <- [10, 100, 250, 500, 1_000, 1_500, 2_000, 2_500, 5_000, 10_000],
      do: {"map #{n} entries", map_entries.(n)}

text_inputs =
  for n <- [1_000, 10_000, 100_000, 1_000_000], do: {"text #{n} chars", text_insert.(n)}

edit_inputs = for n <- [1_000, 10_000, 50_000], do: {"#{n} small edits", small_edits.(n)}

inputs =
  for {name, insert_fn} <- map_inputs ++ text_inputs ++ edit_inputs do
    updates = build.(insert_fn)
    {"#{name} (#{byte_size(updates.v1)} bytes)", updates}
  end

IO.puts("\n=== apply_update normal vs DirtyCpu scheduler (NIF direct) ===\n")

Benchee.run(
  %{
    "apply_update_v1" => fn %{doc: doc, v1: update} ->
      Yex.Nif.apply_update_v1(doc, nil, update)
    end,
    "apply_update_v1_dirty" => fn %{doc: doc, v1: update} ->
      Yex.Nif.apply_update_v1_dirty(doc, nil, update)
    end,
    "apply_update_v2" => fn %{doc: doc, v2: update} ->
      Yex.Nif.apply_update_v2(doc, nil, update)
    end,
    "apply_update_v2_dirty" => fn %{doc: doc, v2: update} ->
      Yex.Nif.apply_update_v2_dirty(doc, nil, update)
    end
  },
  inputs: inputs,
  before_each: fn updates -> Map.put(updates, :doc, Yex.Nif.doc_new()) end,
  # Free the previous doc outside the timed call so destructors do not land in it.
  after_each: fn _ ->
    :erlang.garbage_collect()
    :erlang.yield()
  end,
  time: 3
)

IO.puts("\n=== neighbour wake-up gap during a 200_000 entry apply_update_v1 ===\n")

%{v1: update} = build.(map_entries.(200_000))
IO.puts("update bytes: #{byte_size(update)}")

measure = fn apply_fn ->
  parent = self()

  ticker =
    :erlang.spawn_opt(
      fn ->
        tick = fn tick, worst, last ->
          receive do
            :stop -> send(parent, {:worst_gap_ms, worst})
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
  doc = Yex.Nif.doc_new()
  {us, :ok} = :timer.tc(fn -> apply_fn.(doc, nil, update) end)
  send(ticker, :stop)
  receive do: ({:worst_gap_ms, gap} -> {div(us, 1000), gap})
end

run_pinned = fn apply_fn ->
  parent = self()
  :erlang.spawn_opt(fn -> send(parent, {:result, measure.(apply_fn)}) end, [{:scheduler, 1}])
  receive do: ({:result, result} -> result)
end

for {name, apply_fn} <- [
      {"apply_update_v1", &Yex.Nif.apply_update_v1/3},
      {"apply_update_v1_dirty", &Yex.Nif.apply_update_v1_dirty/3}
    ],
    run <- 1..3 do
  {ms, gap} = run_pinned.(apply_fn)

  IO.puts(
    "#{name} run #{run}: apply #{ms} ms, worst neighbour wake-up gap #{gap} ms (asked for 10)"
  )
end
