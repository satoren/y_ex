# Run with: mix run bench/undo_manager_stress.exs

defmodule UndoManagerStress do
  @doc_size 200_000
  @num_actors 10
  @test_duration_ms 30_000 # 30 seconds

  def run do
    # Create a shared document
    doc = Yex.Doc.new()
    text = Yex.Doc.get_text(doc, "text")
    map = Yex.Doc.get_map(doc, "map")
    array = Yex.Doc.get_array(doc, "array")
    xml = Yex.Doc.get_xml_fragment(doc, "xml")

    # Initialize with some content
    Yex.Text.insert(text, 0, String.duplicate("x", @doc_size))

    IO.puts("\nStarting stress test with #{@num_actors} actors for #{@test_duration_ms/1000} seconds...")

    # Start progress indicator
    spawn_link(fn -> progress_indicator(@test_duration_ms) end)

    # Start actors
    actors = for i <- 1..@num_actors do
      {:ok, manager} = Yex.UndoManager.new(doc, text)
      # Expand scope to include all types
      Yex.UndoManager.expand_scope(manager, map)
      Yex.UndoManager.expand_scope(manager, array)
      Yex.UndoManager.expand_scope(manager, xml)

      spawn_link(fn -> actor_loop(i, doc, text, map, array, xml, manager) end)
    end

    # Run for specified duration
    Process.sleep(@test_duration_ms)

    # Stop actors
    Enum.each(actors, &Process.exit(&1, :normal))

    # Print results
    IO.puts("\nStress test completed")
  end

  defp progress_indicator(total_ms) do
    interval = 1000 # Update every second
    segments = trunc(total_ms / interval)

    Enum.reduce(1..segments, 0, fn i, _ ->
      percent = Float.round(i / segments * 100, 1)
      clear_line()
      IO.write("\rProgress: [#{String.duplicate("=", trunc(i/segments * 40))}#{String.duplicate(" ", 40 - trunc(i/segments * 40))}] #{percent}%")
      Process.sleep(interval)
      i
    end)

    clear_line()
    IO.write("\rProgress: [#{String.duplicate("=", 40)}] 100%\n")
  end

  defp clear_line, do: IO.write("\r#{String.duplicate(" ", 80)}")

  defp actor_loop(id, doc, text, map, array, xml, manager) do
    operation = random_operation()

    try do
      start_time = System.monotonic_time(:millisecond)

      result = case operation do
        :text ->
          pos = :rand.uniform(@doc_size) - 1
          content = random_string(1..10)
          Yex.Text.insert(text, pos, content)

        :map ->
          key = "key_#{:rand.uniform(1000)}"
          value = "value_#{:rand.uniform(1000)}"
          Yex.Map.set(map, key, value)

        :array ->
          value = "item_#{:rand.uniform(1000)}"
          Yex.Array.push(array, value)

        :xml ->
          tag_num = :rand.uniform(100)
          content = "<tag#{tag_num}>content</tag#{tag_num}>"
          Yex.XmlFragment.push(xml, Yex.XmlTextPrelim.from(content))

        :undo ->
          Yex.UndoManager.undo(manager)

        :redo ->
          Yex.UndoManager.redo(manager)
      end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Record metrics for successful operations
      Metrics.record_operation(operation, duration)
      result

    rescue
      e ->
        IO.puts("\nActor #{id} error on #{operation}: #{inspect(e)}")
        Metrics.record_error(operation)
    end

    # Random pause between operations (100-500ms)
    Process.sleep(:rand.uniform(400) + 100)
    actor_loop(id, doc, text, map, array, xml, manager)
  end

  defp random_operation do
    case :rand.uniform(100) do
      x when x <= 7 -> :undo    # 7% chance
      x when x <= 10 -> :redo    # 3% chance
      x when x <= 50 -> :text    # 40% chance
      x when x <= 70 -> :map     # 20% chance
      x when x <= 90 -> :array   # 20% chance
      _             -> :xml      # 10% chance
    end
  end

  defp random_string(range) do
    length = :rand.uniform(Enum.max(range))
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end
end

# Add some basic metrics collection
defmodule Metrics do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:operation_metrics, [:named_table, :public])
    :ets.new(:error_metrics, [:named_table, :public])
    {:ok, %{start_time: System.monotonic_time(:millisecond)}}
  end

  def record_operation(operation, duration_ms) do
    :ets.update_counter(:operation_metrics, operation, {2, 1}, {operation, 0, 0, 0})
    :ets.update_counter(:operation_metrics, operation, {3, duration_ms}, {operation, 0, 0, 0})
    :ets.update_counter(:operation_metrics, operation, {4, 1}, {operation, 0, 0, duration_ms})
  end

  def record_error(operation) do
    :ets.update_counter(:error_metrics, operation, {2, 1}, {operation, 0})
  end

  def print_metrics do
    IO.puts("\nOperation Metrics:")
    IO.puts("================")

    :ets.tab2list(:operation_metrics)
    |> Enum.sort()
    |> Enum.each(fn {op, count, total_ms, _} ->
      avg_ms = if count > 0, do: Float.round(total_ms / count, 2), else: 0
      errors = case :ets.lookup(:error_metrics, op) do
        [{_, error_count}] -> error_count
        [] -> 0
      end
      IO.puts("#{op}: #{count} operations, avg #{avg_ms}ms per operation, #{errors} errors")
    end)
  end
end

# Run the stress test
{:ok, _pid} = Metrics.start_link()
UndoManagerStress.run()
Metrics.print_metrics()
