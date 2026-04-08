# Benchmark for `Yex.DocServer` / `SharedDoc.process_message_v1/3`.
# `sync_step1` measures the synchronous path including `GenServer.call`
# (repeating the same message does not change server state).
# `query_awareness` is also a synchronous response path.
#
#   MIX_ENV=dev mix run benchmark/process_message_v1.exs

alias Yex.{Doc, Array, Sync, Awareness}
alias Yex.Sync.SharedDoc

random_doc_name = fn -> :crypto.strong_rand_bytes(10) end

origin = self()

start_server_with_array = fn cell_count ->
  {:ok, server} =
    SharedDoc.start_link(doc_name: random_doc_name.(), auto_exit: false)

  if cell_count > 0 do
    SharedDoc.update_doc(server, fn doc ->
      arr = Doc.get_array(doc, "array")
      Array.insert_list(arr, 0, List.duplicate("x", cell_count))
    end)
  end

  server
end

IO.puts("\n=== SharedDoc.process_message_v1/3 — {:sync, sync_step1} ===\n")

Benchee.run(
  %{
    "process_message_v1 (sync_step1)" => fn %{server: server, message: message} ->
      SharedDoc.process_message_v1(server, message, origin)
    end
  },
  inputs: %{
    "empty server" => 0,
    "array 100 cells" => 100,
    "array 10_000 cells" => 10_000
  },
  before_scenario: fn cell_count ->
    server = start_server_with_array.(cell_count)

    {:ok, step1} = Sync.get_sync_step1(Doc.new())
    message = Sync.message_encode!({:sync, step1})

    %{server: server, message: message}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)

IO.puts("\n=== SharedDoc.process_message_v1/3 — {:sync, sync_update} ===\n")

Benchee.run(
  %{
    "process_message_v1 (sync_update)" => fn %{server: server, message: message} ->
      SharedDoc.process_message_v1(server, message, origin)
      SharedDoc.get_doc(server) # ensure the update is applied before the next iteration
    end
  },
  inputs: %{
    "array 100 cells" => 100,
    "array 10_000 cells" => 10_000
  },
  before_scenario: fn cell_count ->
    server = start_server_with_array.(0)

    source = Doc.new()
    source_arr = Doc.get_array(source, "array")
    Array.insert_list(source_arr, 0, List.duplicate("x", cell_count))

    {:ok, update} = Yex.encode_state_as_update(source)
    {:ok, sync_update} = Sync.get_update(update)
    message = Sync.message_encode!({:sync, sync_update})

    %{server: server, message: message}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)

IO.puts("\n=== SharedDoc.process_message_v1/3 — :query_awareness ===\n")

query_msg = Sync.message_encode!(:query_awareness)

Benchee.run(
  %{
    "process_message_v1 (query_awareness)" => fn %{server: server} ->
      SharedDoc.process_message_v1(server, query_msg, origin)
    end
  },
  before_scenario: fn _ ->
    {:ok, server} =
      SharedDoc.start_link(doc_name: random_doc_name.(), auto_exit: false)

    %{server: server}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)

IO.puts("\n=== SharedDoc.process_message_v1/3 — {:awareness, update} ===\n")

Benchee.run(
  %{
    "process_message_v1 (awareness_update)" => fn %{server: server, message: message} ->
      SharedDoc.process_message_v1(server, message, origin)
      SharedDoc.get_doc(server) # ensure the update is applied before the next iteration
    end
  },
  before_scenario: fn _ ->
    server = start_server_with_array.(0)

    {:ok, awareness} = Awareness.new(Doc.new())
    Awareness.set_local_state(awareness, %{
      "name" => "benchmark-user",
      "bio" => String.duplicate("x", 420),
      "cursor" => %{"index" => 120, "length" => 8},
      "tags" => Enum.map(1..8, &"tag-#{&1}")
    })
    {:ok, awareness_update} = Awareness.encode_update(awareness)
    message = Sync.message_encode!({:awareness, awareness_update})

    %{server: server, message: message}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)
