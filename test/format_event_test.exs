defmodule Yex.FormatEventTest do
  use ExUnit.Case, async: true

  test "actual Yjs marker IDs and empty-map values match without modifying the prestate" do
    fixture = decode_json!(File.read!(Path.join(__DIR__, "fixtures/format-event-js-v1.json")))

    for scenario <- fixture["cases"] do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{offset_kind: :utf16})
      :ok = Yex.apply_update(doc, :erlang.list_to_binary(scenario["before"]))
      before = Yex.encode_state_as_update!(doc)
      expected = scenario["event"]

      targets =
        Enum.map(expected["changes"], fn c ->
          %{root: nil, nested: id(c["unit"]["type"]), item: id(c["unit"]["item"])}
        end)

      {:ok, actual} =
        Yex.Doc.inspect_format_event(
          doc,
          :erlang.list_to_binary(scenario["update"]),
          "bold",
          targets
        )

      assert actual.inserted == Enum.map(expected["inserted_markers"], &id/1)
      assert actual.deleted == Enum.map(expected["deleted_markers"], &id/1)
      assert length(actual.changes) == length(expected["changes"])

      for {change, index} <- Enum.with_index(actual.changes) do
        assert change.target_index == index
        wanted = Enum.at(expected["changes"], index)

        for side <- [:before, :after] do
          state = Map.fetch!(change, side)
          wanted = wanted[Atom.to_string(side)]
          assert state.marker == if(is_map(wanted["marker"]), do: id(wanted["marker"]), else: nil)
          assert state.value == if(wanted["enabled"], do: %{}, else: nil)
        end
      end

      assert Yex.encode_state_as_update!(doc) == before
    end
  end

  test "malformed target shape refuses" do
    doc = Yex.Doc.with_options(%Yex.Doc.Options{offset_kind: :utf16})

    assert_raise ArgumentError, fn ->
      Yex.Doc.inspect_format_event(doc, <<0, 0>>, "bold", [
        %{root: "x", nested: %{client: 1, clock: 0}, item: %{client: 1, clock: 0}}
      ])
    end
  end

  test "new markers on an existing client preserve unrelated link marks without panic" do
    fixture =
      decode_json!(
        File.read!(Path.join(__DIR__, "fixtures/format-event-existing-client-v1.json"))
      )

    doc = Yex.Doc.with_options(%Yex.Doc.Options{offset_kind: :utf16})
    :ok = Yex.apply_update(doc, :erlang.list_to_binary(fixture["before"]))
    before = Yex.encode_state_as_update!(doc)

    targets =
      for clock <- 2..6,
          do: %{
            root: nil,
            nested: %{client: 75_750_343, clock: 1},
            item: %{client: 75_750_343, clock: clock}
          }

    {:ok, event} =
      Yex.Doc.inspect_format_event(
        doc,
        :erlang.list_to_binary(fixture["update"]),
        "bold",
        targets
      )

    assert event.inserted == [%{client: 0, clock: 2}, %{client: 0, clock: 3}]
    assert length(event.changes) == 5
    assert Enum.all?(event.changes, &(&1.after.value == %{}))
    assert Yex.encode_state_as_update!(doc) == before
  end

  defp decode_json!(bytes) do
    if Code.ensure_loaded?(Jason), do: Jason.decode!(bytes), else: :json.decode(bytes)
  end

  defp id(v), do: %{client: v["client"], clock: v["clock"]}
end
