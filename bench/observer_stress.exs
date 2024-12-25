# Run with: mix run bench/observer_stress.exs

defmodule ObserverStress do
  @num_concurrent_actors 50  # How many actors to keep active at once
  @total_actors 1000        # Total number of actors to create over the test
  @actor_lifetime_ms 5000   # How long each actor lives
  @test_duration_ms 30_000  # Total test duration

  def run do
    # Create a shared document
    doc = Yex.Doc.new()
    text = Yex.Doc.get_text(doc, "text")

    IO.puts("\nStarting observer stress test:")
    IO.puts("- #{@num_concurrent_actors} concurrent actors")
    IO.puts("- #{@total_actors} total actors")
    IO.puts("- #{@actor_lifetime_ms}ms actor lifetime")
    IO.puts("- #{@test_duration_ms}ms test duration")

    # Start progress indicator
    spawn_link(fn -> progress_indicator(@test_duration_ms) end)

    # Start actor spawner
    spawn_link(fn -> actor_spawner(doc, text) end)

    # Run for specified duration
    Process.sleep(@test_duration_ms)

    # Print results
    IO.puts("\nStress test completed")

    # Give time for final metrics collection
    Process.sleep(1000)
  end

  defp actor_spawner(doc, text) do
    actor_spawner(doc, text, 0, MapSet.new())
  end

  defp actor_spawner(doc, text, count, active_pids) when count < @total_actors do
    # Remove any finished actors
    active_pids =
      active_pids
      |> Enum.filter(&Process.alive?/1)
      |> MapSet.new()

    # Spawn new actors if we're below the concurrent limit
    active_pids =
      if MapSet.size(active_pids) < @num_concurrent_actors do
        pid = spawn_actor(doc, text, count)
        MapSet.put(active_pids, pid)
      else
        active_pids
      end

    Process.sleep(100)  # Control spawn rate
    actor_spawner(doc, text, count + 1, active_pids)
  end

  defp actor_spawner(_doc, _text, count, _active_pids) do
    MemoryMetrics.record_final_actors(count)
  end

  defp spawn_actor(doc, text, id) do
    spawn_link(fn ->
      start_time = System.monotonic_time(:millisecond)

      try do
        {:ok, manager} = Yex.UndoManager.new(doc, text)

        # Add multiple observers
        {:ok, manager} = Yex.UndoManager.on_item_added(manager, fn _event ->
          %{actor_id: id, type: :added}
        end)

        {:ok, manager} = Yex.UndoManager.on_item_updated(manager, fn _event ->
          %{actor_id: id, type: :updated}
        end)

        {:ok, manager} = Yex.UndoManager.on_item_popped(manager, fn _id, _event ->
          %{actor_id: id, type: :popped}
        end)

        # Record successful observer creation
        MemoryMetrics.record_observer_created()

        # Do some work
        Enum.each(1..5, fn _ ->
          Yex.Text.insert(text, 0, "test")
          Yex.UndoManager.undo(manager)
          Process.sleep(:rand.uniform(500))
        end)

        # Live for specified duration
        remaining_time = @actor_lifetime_ms - (System.monotonic_time(:millisecond) - start_time)
        if remaining_time > 0, do: Process.sleep(remaining_time)

        # Record successful cleanup
        MemoryMetrics.record_observer_cleaned()

      rescue
        e ->
          IO.puts("\nActor #{id} error: #{inspect(e)}")
          MemoryMetrics.record_error()
      end
    end)
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
      observers_created: 0,
      observers_cleaned: 0,
      errors: 0,
      final_actors: 0
    }}
  end

  def record_memory_point(memory) do
    time = System.monotonic_time(:millisecond)
    :ets.insert(:memory_metrics, {{:memory, time}, memory})
  end

  def record_observer_created do
    GenServer.cast(__MODULE__, :observer_created)
  end

  def record_observer_cleaned do
    GenServer.cast(__MODULE__, :observer_cleaned)
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

    IO.puts("\nMemory Metrics:")
    IO.puts("==============")
    IO.puts("Total actors created: #{state.final_actors || 0}")
    IO.puts("Observers created: #{state.observers_created}")
    IO.puts("Observers cleaned: #{state.observers_cleaned}")
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
  def handle_cast(:observer_created, state) do
    {:noreply, %{state | observers_created: state.observers_created + 1}}
  end

  def handle_cast(:observer_cleaned, state) do
    {:noreply, %{state | observers_cleaned: state.observers_cleaned + 1}}
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
ObserverStress.run()
MemoryMetrics.print_metrics()
