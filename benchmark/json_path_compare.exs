# Benchmark: JSONPath API vs direct list-returning NIF
#
# Run with:
#   MIX_ENV=dev mix run benchmark/json_path_compare.exs

alias Yex.Doc

require Yex.Doc

path = "$.users..friends.*.nick"

build_doc = fn user_count, friend_count ->
  doc = Doc.new()
  users = Doc.get_array(doc, "users")

  for i <- 1..user_count do
    friends = for j <- 1..friend_count, do: %{"nick" => "u#{i}-f#{j}"}

    Yex.Array.push(users, %{
      "name" => "user-#{i}",
      "friends" => friends,
      "meta" => %{"active" => true, "idx" => i}
    })
  end

  doc
end

Benchee.run(
  %{
    "iterator API (Yex.json_path/2)" => fn %{doc: doc, path: path} ->
      # Ensure run_in_worker_process executes inline in the benchmark process.
      inline_doc = %{doc | worker_pid: self()}
      {:ok, values} = Yex.json_path(inline_doc, path)
      values
    end,
    "direct list NIF (transaction_json_path_all)" => fn %{doc: doc, path: path} ->
      {:ok, values} = Yex.Nif.transaction_json_path_all(doc, nil, path)
      values
    end
  },
  inputs: %{
    "100 users x 5 friends (500 hits)" => %{users: 100, friends: 5},
    "500 users x 5 friends (2_500 hits)" => %{users: 500, friends: 5}
  },
  before_scenario: fn %{users: users, friends: friends} ->
    doc = build_doc.(users, friends)
    %{doc: doc, path: path}
  end,
  time: 5,
  memory_time: 2
)
