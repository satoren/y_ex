defmodule ArrayInsertBench do
  @moduledoc """
  Benchmark for sequential string insertion at index 0 in Yex.Array
  """

  def run_sequential_inserts(array, string_length, num_inserts) do
    string = String.duplicate("a", string_length)
    for _ <- 1..num_inserts do
      Yex.Array.insert(array, 0, string)
    end
  end

  def benchmark do
    inputs = %{
      "string length 10" => 10,
      "string length 100" => 100,
      "string length 1000" => 1_000
    }

    num_inserts_list = [1, 10, 100]

    benchmarks =
      for n <- num_inserts_list, into: %{} do
        name = "#{n} sequential insert(s)"

        benchmark_fn = fn string_length ->
          doc = Yex.Doc.new()
          array = Yex.Doc.get_array(doc, "array")
          run_sequential_inserts(array, string_length, n)
        end

        {name, benchmark_fn}
      end

    Benchee.run(
      benchmarks,
      inputs: inputs,
      time: 5,
      memory_time: 2,
      warmup: 1
    )
  end
end

# Run the benchmark
ArrayInsertBench.benchmark()
