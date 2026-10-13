defmodule Yex.AwarenessTest do
  use ExUnit.Case, async: true
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

  test "monitor_update with metadata" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    _monitor_ref = Awareness.monitor_update(awareness, metadata: %{"key" => "value"})
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert_received {:awareness_update, %{removed: [], added: [10], updated: []}, _origin,
                     %{"key" => "value"}}
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

  test "monitor_change with metadata" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    _monitor_ref = Awareness.monitor_change(awareness, metadata: %{"key" => "value"})
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert_received {:awareness_change, %{removed: [], added: [10], updated: []}, _origin,
                     %{"key" => "value"}}
  end

  test "remove_states" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
    Awareness.set_local_state(awareness, %{"key" => "value"})

    assert [10] === Awareness.get_client_ids(awareness)
    Awareness.remove_states(awareness, [10])
    assert [] === Awareness.get_client_ids(awareness)
  end

  test "encode_update and remove_states raise ArgumentError for a client id outside the 53-bit range" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 5}))
    Awareness.set_local_state(awareness, %{"key" => "value"})
    aliased = Bitwise.bsl(1, 53) + 5

    assert_raise ArgumentError, "client id must be in 0..9007199254740991", fn ->
      Awareness.encode_update(awareness, [aliased])
    end

    assert_raise ArgumentError, "client id must be in 0..9007199254740991", fn ->
      Awareness.remove_states(awareness, [5, aliased])
    end

    assert [5] === Awareness.get_client_ids(awareness)
  end

  test "apply_update rejects a client id of 2^53 or more instead of aliasing it" do
    {:ok, awareness} = Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 5}))
    Awareness.set_local_state(awareness, %{"key" => "value"})

    # Client 2^53 + 5 with clock 1 and a null state, which would remove client 5.
    update = <<1, 133, 128, 128, 128, 128, 128, 128, 16, 1, 4, "null">>

    assert {:error, {:encoding_exception, msg}} = Awareness.apply_update(awareness, update)
    assert msg =~ "client id 9007199254740997 is out of range"
    assert [5] === Awareness.get_client_ids(awareness)
    assert %{"key" => "value"} === Awareness.get_local_state(awareness)
  end

  test "apply_update with origin" do
    {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
    Yex.Awareness.monitor_change(awareness)
    Yex.Awareness.apply_update(awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>, "origin")

    assert_receive {:awareness_change, %{removed: [], added: [2_230_489_810], updated: []},
                    "origin", _awareness}
  end
end
