alias Yex.{Doc, Array}
alias Yex.Sync.SharedDoc

Benchee.run(
  %{
    "Array.fetch/2" => fn %{array: array, index: index} ->
      Doc.transaction(array.doc, fn ->
        Array.fetch(array, index)
      end)
    end,
    "Enum.at/2 (optimized)" => fn %{array: array, index: index} ->
      Doc.transaction(array.doc, fn ->
        Enum.at(array, index)
      end)
    end,
    "Enum.slice/2 (single element)" => fn %{array: array, index: index} ->
      Doc.transaction(array.doc, fn ->
        Enum.slice(array, index, 1) |> List.first()
      end)
    end,
    "to_list then access" => fn %{array: array, index: index} ->
      Doc.transaction(array.doc, fn ->
        Array.to_list(array) |> Enum.at(index)
      end)
    end
  },
  inputs: %{
    "10 elements" => 10,
    "100 elements" => 100,
    "1000 elements" => 1000
  },
  before_scenario: fn size ->
      {:ok, pid} = SharedDoc.start_link(doc_name: :crypto.strong_rand_bytes(10))
    doc = SharedDoc.get_doc(pid)
    array = Doc.get_array(doc, "array")
    Array.insert_list(array, 0, Enum.to_list(1..size))
    # Access middle element
    index = div(size, 2)
    %{array: array, index: index}
  end,
  memory_time: 2,
  time: 5
)
