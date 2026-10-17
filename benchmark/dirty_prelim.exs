# Benchmark for Yex.Nif.dirty_prelim_values/0.
# as_prelim/1 costs what the converted subtree holds. For each shape this finds how many
# values a tree counts (the smallest budget the normal NIF accepts) and the median time of
# converting it on a normal scheduler, across sizes.
# Limit: largest power of two below the smallest value count whose median exceeds 1 ms.
# Run with: MIX_ENV=dev mix run benchmark/dirty_prelim.exs

alias Yex.{Doc, MapPrelim, ArrayPrelim, TextPrelim, XmlElementPrelim, XmlTextPrelim}

shapes = %{
  # Elements with an attribute, a formatted text and a nested element: the usual
  # rich-text tree.
  "xml paragraphs" => fn n ->
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")

    Doc.transaction(doc, fn ->
      for i <- 1..n do
        Yex.XmlFragment.push(
          frag,
          XmlElementPrelim.new(
            "p",
            [
              XmlTextPrelim.from("para #{i}"),
              XmlElementPrelim.new("b", [XmlTextPrelim.from("b")])
            ],
            %{"class" => "c#{i}"}
          )
        )
      end
    end)

    frag
  end,
  # Nested shared maps, each with an array, a text and a plain value.
  "nested maps" => fn n ->
    doc = Doc.new()
    map = Doc.get_map(doc, "m")

    Doc.transaction(doc, fn ->
      for i <- 1..n do
        Yex.Map.set(
          map,
          "k#{i}",
          MapPrelim.from(%{
            "list" => ArrayPrelim.from([1, 2]),
            "text" => TextPrelim.from("t#{i}"),
            "plain" => %{"a" => [1, 2]}
          })
        )
      end
    end)

    map
  end,
  # Plain values in an array: one value each, the cheapest shape per value.
  "array of numbers" => fn n ->
    doc = Doc.new()
    array = Doc.get_array(doc, "a")
    Yex.Array.insert_list(array, 0, Enum.to_list(1..n))
    array
  end
}

# The smallest budget the normal NIF converts the tree within is its value count.
count_values = fn type ->
  Stream.iterate(1, &(&1 * 2))
  |> Enum.find(&(Yex.Nif.shared_type_as_prelim(type, nil, &1) != :dirty))
  |> then(fn high ->
    Enum.reduce_while(Stream.cycle([:ok]), {div(high, 2), high}, fn _, {low, high} ->
      if high - low <= 1 do
        {:halt, high}
      else
        mid = div(low + high, 2)

        if Yex.Nif.shared_type_as_prelim(type, nil, mid) == :dirty,
          do: {:cont, {mid, high}},
          else: {:cont, {low, mid}}
      end
    end)
  end)
end

median_us = fn fun ->
  times = for _ <- 1..51, do: elem(:timer.tc(fun), 0)
  times |> Enum.sort() |> Enum.at(25)
end

IO.puts("shape\tsize\tvalues\tnormal median (us)")

for {name, build} <- shapes, n <- [50, 100, 200, 400, 800, 1_600, 3_200, 6_400] do
  type = build.(n)
  values = count_values.(type)
  # A budget above the value count, so the normal NIF does all the work.
  us = median_us.(fn -> Yex.Nif.shared_type_as_prelim(type, nil, values) end)
  IO.puts("#{name}\t#{n}\t#{values}\t#{us}")
end
