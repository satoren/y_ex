defmodule Yex.AwarenessTest do
  use ExUnit.Case
  alias Yex.Awareness
  doctest Awareness

  test "client_id" do
    doc = Yex.Doc.new()
    {:ok, awareness} = Awareness.new(doc)

    assert is_number(Awareness.client_id(awareness))
  end

  test "set_local_state" do
    doc = Yex.Doc.new()
    {:ok, awareness} = Awareness.new(doc)

    Awareness.set_local_state(awareness, %{"key" => "value"})
    assert %{"key" => "value"} === Awareness.get_local_state(awareness)
  end

  test "monitor_update" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    monitor_ref = Awareness.monitor_update(awareness)
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert_received {:awareness_update, %{removed: [], added: [10], updated: []}, _origin,
                     _awareness}

    Awareness.demonitor_update(monitor_ref)
    Awareness.set_local_state(awareness, %{"key2" => "value2"})
    refute_received {:awareness_update, _, _origin, _awareness}
  end

  test "monitor_change" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    monitor_ref = Awareness.monitor_change(awareness)
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert_received {:awareness_change, %{removed: [], added: [10], updated: []}, _origin,
                     _awareness}

    Awareness.demonitor_change(monitor_ref)
    Awareness.set_local_state(awareness, %{"key2" => "value2"})
    refute_received {:awareness_change, _, _origin, _awareness}
  end

  test "remove_states" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert [10] === Awareness.get_client_ids(awareness)
    Awareness.remove_states(awareness, [10])
    assert [] === Awareness.get_client_ids(awareness)
  end

  test "apply_update with origin" do
    {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
    Yex.Awareness.monitor_change(awareness)
    Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>, "origin")

    assert_receive {:awareness_change, %{removed: [], added: [2_230_489_810], updated: []},
                    "origin", _awareness}
  end
end
