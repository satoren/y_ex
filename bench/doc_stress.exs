# Run with: mix run bench/doc_stress.exs

defmodule DocStress do
  @num_concurrent_actors 50  # How many actors to keep active at once
  @total_actors 1000        # Total number of actors to create over the test
  @actor_lifetime_ms 5000   # How long each actor lives
  @test_duration_ms 30_000  # Total test duration

  def run do
    # Create a shared document
    doc = Yex.Doc.new()
    text = Yex.Doc.get_text(doc, "text")
    map = Yex.Doc.get_map(doc, "map")
    array = Yex.Doc.get_array(doc, "array")
    xml = Yex.Doc.get_xml_fragment(doc, "xml")

    # Initialize with some content
    Yex.Text.insert(text, 0, String.duplicate("x", 200_000))

    IO.puts("\nStarting doc stress test:")
    IO.puts("- #{@num_concurrent_actors} concurrent actors")
    IO.puts("- #{@total_actors} total actors")
    IO.puts("- #{@actor_lifetime_ms}ms actor lifetime")
    IO.puts("- #{@test_duration_ms}ms test duration")

    # Start progress indicator
    spawn_link(fn -> progress_indicator(@test_duration_ms) end)

    # Start actor spawner
    spawn_link(fn -> actor_spawner(doc, text, map, array, xml) end)

    # Run for specified duration
    Process.sleep(@test_duration_ms)

    # Print results
    IO.puts("\nStress test completed")

    # Give time for final metrics collection
    Process.sleep(1000)
  end

  defp actor_spawner(doc, text, map, array, xml) do
    actor_spawner(doc, text, map, array, xml, 0, MapSet.new())
  end

  defp actor_spawner(doc, text, map, array, xml, count, active_pids) when count < @total_actors do
    # Remove any finished actors
    active_pids =
      active_pids
      |> Enum.filter(&Process.alive?/1)
      |> MapSet.new()

    # Spawn new actors if we're below the concurrent limit
    active_pids =
      if MapSet.size(active_pids) < @num_concurrent_actors do
        pid = spawn_actor(doc, text, map, array, xml, count)
        MapSet.put(active_pids, pid)
      else
        active_pids
      end

    Process.sleep(100)  # Control spawn rate
    actor_spawner(doc, text, map, array, xml, count + 1, active_pids)
  end

  defp actor_spawner(_doc, _text, _map, _array, _xml, count, _active_pids) do
    MemoryMetrics.record_final_actors(count)
  end

  defp spawn_actor(doc, text, map, array, xml, id) do
    spawn_link(fn ->
      start_time = System.monotonic_time(:millisecond)

      try do
        # Keep doc reference alive while working with shared types
        _doc_ref = doc

        # Do some work with all types
        Enum.each(1..10, fn _ ->
          operation = random_operation()

          case operation do
            :text ->
              pos = :rand.uniform(200_000) - 1
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
          end
        end)

        # Record successful operations
        MemoryMetrics.record_operations_completed()

        # Live for specified duration
        remaining_time = @actor_lifetime_ms - (System.monotonic_time(:millisecond) - start_time)
        if remaining_time > 0, do: Process.sleep(remaining_time)

      rescue
        e ->
          IO.puts("\nActor #{id} error: #{inspect(e)}")
          MemoryMetrics.record_error()
      end
    end)
  end

  defp random_operation do
    case :rand.uniform(100) do
      x when x <= 40 -> :text    # 40% chance
      x when x <= 70 -> :map     # 30% chance
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

  defp progress_indicator(total_ms) do
    interval = 1000 # Update every second
    segments = trunc(total_ms / interval)

    Enum.reduce(1..segments, 0, fn i, _ ->
      percent = Float.round(i / segments * 100, 1)
      memory = :erlang.memory()

      clear_line()
      IO.write("\rProgress: [#{String.duplicate("=", trunc(i/segments * 40))}#{String.duplicate(" ", 40 - trunc(i/segments * 40))}] #{percent}%")
      IO.write(" | Memory: #{format_bytes(memory[:total])}")

      MemoryMetrics.record_memory_point(memory)
      Process.sleep(interval)
      i
    end)

    clear_line()
    IO.write("\rProgress: [#{String.duplicate("=", 40)}] 100%\n")
  end

  defp clear_line, do: IO.write("\r#{String.duplicate(" ", 120)}")

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)}MB"
end

defmodule MemoryMetrics do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:memory_metrics, [:named_table, :public])
    {:ok, %{
      start_time: System.monotonic_time(:millisecond),
      operations_completed: 0,
      errors: 0,
      final_actors: 0
    }}
  end

  def record_memory_point(memory) do
    time = System.monotonic_time(:millisecond)
    :ets.insert(:memory_metrics, {{:memory, time}, memory})
  end

  def record_operations_completed do
    GenServer.cast(__MODULE__, :operation_completed)
  end

  def record_error do
    GenServer.cast(__MODULE__, :error)
  end

  def record_final_actors(count) do
    GenServer.cast(__MODULE__, {:final_actors, count})
  end

  def print_metrics do
    state = GenServer.call(__MODULE__, :get_state)
    memory_points = :ets.match_object(:memory_metrics, {{:memory, :_}, :_})

    IO.puts("\nOperation Metrics:")
    IO.puts("================")
    IO.puts("Total actors created: #{state.final_actors}")
    IO.puts("Operations completed: #{state.operations_completed}")
    IO.puts("Errors: #{state.errors}")

    case memory_points do
      [] ->
        IO.puts("No memory data collected")

      points ->
        {min_memory, max_memory, avg_memory} = analyze_memory(points)
        IO.puts("\nMemory Usage:")
        IO.puts("Min: #{format_bytes(min_memory)}")
        IO.puts("Max: #{format_bytes(max_memory)}")
        IO.puts("Avg: #{format_bytes(trunc(avg_memory))}")
    end
  end

  defp analyze_memory(points) do
    memories = Enum.map(points, fn {{:memory, _}, memory} -> memory[:total] end)
    {
      Enum.min(memories),
      Enum.max(memories),
      Enum.sum(memories) / length(memories)
    }
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)}MB"

  # Server callbacks
  def handle_cast(:operation_completed, state) do
    {:noreply, %{state | operations_completed: state.operations_completed + 1}}
  end

  def handle_cast(:error, state) do
    {:noreply, %{state | errors: state.errors + 1}}
  end

  def handle_cast({:final_actors, count}, state) do
    {:noreply, Map.put(state, :final_actors, count)}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end

# Run the stress test
{:ok, _pid} = MemoryMetrics.start_link()
DocStress.run()
MemoryMetrics.print_metrics()
