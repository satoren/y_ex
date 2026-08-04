# Benchmark for `apply_update_v1/2` and `apply_update_v2/2` NIFs.
# Measures only decode + apply cost; doc creation is in before_each (not measured).
# Run with: MIX_ENV=prod mix run benchmark/apply_update.exs

alias Yex.{Doc, Array, Text}

build_update_v1 = fn insert_fn ->
  src = Doc.new()
  insert_fn.(src)
  {:ok, update} = Yex.encode_state_as_update_v1(src)
  update
end

build_update_v2 = fn insert_fn ->
  src = Doc.new()
  insert_fn.(src)
  {:ok, update} = Yex.encode_state_as_update_v2(src)
  update
end

IO.puts("\n=== apply_update_v1 vs apply_update_v2 (NIF direct) ===\n")

Benchee.run(
  %{
    # Call NIF directly: no worker_pid routing, so before_each doc survives into memory measurement
    "apply_update_v1" => fn %{doc: doc, update_v1: update} ->
      Yex.Nif.apply_update_v1(doc, nil, update)
    end,
    "apply_update_v2" => fn %{doc: doc, update_v2: update} ->
      Yex.Nif.apply_update_v2(doc, nil, update)
    end
  },
  inputs: %{
    "text 100 chars" => fn doc ->
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, String.duplicate("x", 100))
    end,
    "text 10_000 chars" => fn doc ->
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, String.duplicate("x", 10_000))
    end,
    "array 100 items" => fn doc ->
      arr = Doc.get_array(doc, "array")
      Array.insert_list(arr, 0, List.duplicate("x", 100))
    end,
    "array 10_000 items" => fn doc ->
      arr = Doc.get_array(doc, "array")
      Array.insert_list(arr, 0, List.duplicate("x", 10_000))
    end
  },
  before_scenario: fn insert_fn ->
    %{
      update_v1: build_update_v1.(insert_fn),
      update_v2: build_update_v2.(insert_fn)
    }
  end,
  before_each: fn %{update_v1: u1, update_v2: u2} ->
    # fresh doc per iteration so accumulated state does not affect timing
    %{doc: Yex.Nif.doc_new(), update_v1: u1, update_v2: u2}
  end,
  memory_time: 2,
  time: 5
)
