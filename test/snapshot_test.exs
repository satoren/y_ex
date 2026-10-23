defmodule Yex.SnapshotTest do
  use ExUnit.Case, async: true
  doctest Yex.Snapshot

  # Fixtures generated with yjs 13.6:
  #
  #   const a = new Y.Doc({ gc: false }); a.clientID = 1
  #   const t = a.getText('text')
  #   t.insert(0, 'abc'); const s1 = Y.snapshot(a)
  #   t.delete(1, 1); t.insert(2, 'd', { bold: true }); const s2 = Y.snapshot(a)
  #   // @update_a = Y.encodeStateAsUpdate(a), @s1_v1 = Y.encodeSnapshot(s1), @s2_v2 = Y.encodeSnapshotV2(s2), ...
  #   const b = new Y.Doc({ gc: false }); b.clientID = 5; Y.applyUpdate(b, Y.encodeStateAsUpdate(a))
  #   b.transact(() => { b.getText('text').insert(0, 'zz'); b.getText('text').delete(0, 1) })
  #   // @update_b = Y.encodeStateAsUpdate(b), @multi_v1 = Y.encodeSnapshot(Y.snapshot(b)), ...
  @update_a Base.decode16!(
              "010601000401047465787401618401000162840101016386010204626f6c640474727565840103016486010404626f6c64046e756c6c0101010101",
              case: :lower
            )
  @update_b Base.decode16!(
              "02020500440100017ac405000100017a0601000401047465787401618401000162840101016386010204626f6c640474727565840103016486010404626f6c64046e756c6c020501000101010101",
              case: :lower
            )
  @s1_v1 Base.decode16!("00010103", case: :lower)
  @s1_v2 Base.decode16!("00010103", case: :lower)
  @s2_v1 Base.decode16!("0101010101010106", case: :lower)
  @s2_v2 Base.decode16!("0101010100010106", case: :lower)
  @multi_v1 Base.decode16!("0205010001010101010205020106", case: :lower)
  @multi_v2 Base.decode16!("0205010000010101000205020106", case: :lower)

  # Owns docs in the cross-process tests; runs what Yex.Doc.run_in_worker_process sends.
  defmodule Worker do
    use GenServer
    def start_link(_), do: GenServer.start_link(__MODULE__, nil)
    @impl true
    def init(state), do: {:ok, state}
    @impl true
    def handle_call({Yex.Doc, :run, fun}, _from, state), do: {:reply, fun.(), state}
  end

  defp doc_with(update, client_id \\ 1, skip_gc \\ true) do
    doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: client_id, skip_gc: skip_gc})
    :ok = Yex.apply_update_v1(doc, update)
    doc
  end

  defp decode!(bytes, :v1), do: elem({:ok, _} = Yex.Snapshot.decode_v1(bytes), 1)
  defp decode!(bytes, :v2), do: elem({:ok, _} = Yex.Snapshot.decode_v2(bytes), 1)

  defp ychange(type, clock), do: %{"type" => type, "id" => %{"client" => 1, "clock" => clock}}

  # "X" and "Y" merge into one block "XY" whose right origin is "a"; the snapshot ends
  # between them, so encoding has to cut that block.
  defp mid_block_snapshot(doc, text) do
    Yex.Text.insert(text, 0, "abc")
    Yex.Text.insert(text, 0, "X")
    {:ok, snapshot} = Yex.snapshot(doc)
    Yex.Text.insert(text, 1, "Y")
    snapshot
  end

  defp assert_restores(update, apply, expected) do
    restored = Yex.Doc.new()
    assert :ok = apply.(restored, update)
    assert Yex.Text.to_string(Yex.Doc.get_text(restored, "text")) == expected
  end

  # The monitors that saw nothing still report a real edit.
  defp assert_monitors_live(doc, text) do
    Yex.Text.insert(text, 0, "!")
    assert_receive {:update_v1, _, _, ^doc}
    assert_receive {:transaction_cleanup, _, _, ^doc}
  end

  describe "snapshot / encode_state_from_snapshot" do
    test "Yex.Snapshot.encode_state_v1/1 and encode_state_v2/1 are available" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)

      assert {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot)
      assert {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot)
      assert is_binary(update_v1)
      assert is_binary(update_v2)
    end

    test "Snapshot.encode_state_v1 restores point-in-time state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 5, " World")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "Snapshot.encode_state_v2 restores point-in-time state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 5, " World")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v2(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "snapshot encoding returns encoding_exception when GC is enabled" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)

      assert {:error, {:encoding_exception, _}} =
               Yex.Snapshot.encode_state_v1(snapshot)

      assert {:error, {:encoding_exception, _}} =
               Yex.Snapshot.encode_state_v2(snapshot)
    end

    test "a gc doc returns encoding_exception and stays usable" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: false})
      text = Yex.Doc.get_text(doc, "text")
      snapshot = mid_block_snapshot(doc, text)
      {:ok, state_vector} = Yex.encode_state_vector(doc)
      {:ok, _} = Yex.Doc.monitor_update(doc)

      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.encode_state_v1(snapshot, doc)
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.encode_state_v2(snapshot, doc)

      refute_receive {:update_v1, _, _, _}, 50
      assert Yex.encode_state_vector(doc) == {:ok, state_vector}
      assert Yex.Text.to_string(text) == "XYabc"
    end

    test "snapshot APIs work inside explicit transaction context" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      update_from_snapshot =
        Yex.Doc.transaction(doc, fn ->
          Yex.Text.insert(text, 0, "Hello")
          {:ok, snapshot} = Yex.snapshot(doc)
          Yex.Text.insert(text, 5, " World")
          {:ok, update} = Yex.Snapshot.encode_state_v1(snapshot)
          update
        end)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "Snapshot.encode_state_v1 produces parseable v1 update" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abc")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 3, "def")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)
      assert {:ok, debug} = Yex.update_debug_v1(update_from_snapshot)
      assert is_binary(debug)
      assert byte_size(debug) > 0
    end

    test "Snapshot.encode_state_v2 produces parseable v2 update" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abc")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 3, "def")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)
      assert {:ok, debug} = Yex.update_debug_v2(update_from_snapshot)
      assert is_binary(debug)
      assert byte_size(debug) > 0
    end

    test "empty snapshot can be encoded and restores empty state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      {:ok, snapshot} = Yex.snapshot(doc)

      Yex.Text.insert(text, 0, "newer")
      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == ""
      assert Yex.Text.to_string(text) == "newer"
    end

    test "snapshot before delete restores pre-delete content" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abcdef")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.delete(text, 2, 3)

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "abcdef"
      assert Yex.Text.to_string(text) == "abf"
    end

    test "snapshot works for array shared type" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      array = Yex.Doc.get_array(doc, "arr")

      Yex.Array.insert_list(array, 0, [1, 2])
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Array.insert_list(array, 2, [3, 4])

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)

      restored = Yex.Doc.new()
      restored_array = Yex.Doc.get_array(restored, "arr")
      :ok = Yex.apply_update_v2(restored, update_from_snapshot)

      assert Yex.Array.to_list(restored_array) == [1.0, 2.0]
      assert Yex.Array.to_list(array) == [1.0, 2.0, 3.0, 4.0]
    end

    test "a snapshot clock inside a block encodes a valid update" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      snapshot = mid_block_snapshot(doc, text)
      {:ok, state_vector} = Yex.encode_state_vector(doc)
      {:ok, _} = Yex.Doc.monitor_update(doc)
      {:ok, _} = Yex.Doc.monitor_transaction_cleanup(doc)

      {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot)
      {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot)

      assert_restores(update_v1, &Yex.apply_update_v1/2, "Xabc")
      assert_restores(update_v2, &Yex.apply_update_v2/2, "Xabc")
      # the split leaves the content and state vector unchanged and emits no event
      refute_receive {:update_v1, _, _, _}, 50
      refute_receive {:transaction_cleanup, _, _, _}
      assert Yex.encode_state_vector(doc) == {:ok, state_vector}
      assert Yex.Text.to_string(text) == "XYabc"
      assert_monitors_live(doc, text)
    end

    test "a snapshot clock inside a block encodes a valid update inside a transaction" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      snapshot = mid_block_snapshot(doc, text)

      {update_v1, update_v2} =
        Yex.Doc.transaction(doc, fn ->
          Yex.Text.insert(text, 5, "!")
          {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot)
          {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot)
          {update_v1, update_v2}
        end)

      assert_restores(update_v1, &Yex.apply_update_v1/2, "Xabc")
      assert_restores(update_v2, &Yex.apply_update_v2/2, "Xabc")
      assert Yex.Text.to_string(text) == "XYabc!"
    end
  end

  describe "encode/decode snapshots" do
    test "a live snapshot encodes to the exact yjs bytes, multi-client included" do
      {:ok, snapshot} = Yex.snapshot(doc_with(@update_b, 5))
      assert Yex.Snapshot.encode_v1(snapshot) == {:ok, @multi_v1}
      assert Yex.Snapshot.encode_v2(snapshot) == {:ok, @multi_v2}

      {:ok, snapshot} = Yex.snapshot(doc_with(@update_a))
      assert Yex.Snapshot.encode_v1(snapshot) == {:ok, @s2_v1}
      assert Yex.Snapshot.encode_v2(snapshot) == {:ok, @s2_v2}
    end

    test "yjs bytes decode to detached snapshots and re-encode unchanged" do
      for {v1, v2} <- [
            {@s1_v1, @s1_v2},
            {@s2_v1, @s2_v2},
            {@multi_v1, @multi_v2},
            {<<0, 0>>, <<0, 0>>}
          ] do
        assert {:ok, %Yex.Snapshot{doc: nil} = from_v1} = Yex.Snapshot.decode_v1(v1)
        assert {:ok, %Yex.Snapshot{doc: nil} = from_v2} = Yex.Snapshot.decode_v2(v2)
        assert Yex.Snapshot.encode_v1(from_v1) == {:ok, v1}
        assert Yex.Snapshot.encode_v2(from_v2) == {:ok, v2}
        assert Yex.Snapshot.equal?(from_v1, from_v2)
      end
    end

    test "malformed bytes return an encoding_exception" do
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.decode_v1(<<0x80>>)
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.decode_v2(<<1>>)
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.decode_v1(<<>>)
    end

    test "a hand-built snapshot with an invalid reference raises" do
      assert_raise ArgumentError, fn ->
        Yex.Snapshot.encode_v2(%Yex.Snapshot{doc: nil, reference: <<0x80>>})
      end
    end

    test "zero-clock state vector entries are dropped" do
      snapshot = decode!(<<0, 1, 1, 0>>, :v1)
      assert Yex.Snapshot.encode_v1(snapshot) == {:ok, <<0, 0>>}
      assert {:ok, _} = Yex.Snapshot.encode_state_v1(snapshot, doc_with(@update_a))
    end

    test "equal?/2 compares state, not the owning doc" do
      doc = doc_with(@update_a)
      {:ok, live} = Yex.snapshot(doc)
      {:ok, other} = Yex.snapshot(doc_with(@update_a, 2))

      assert Yex.Snapshot.equal?(live, decode!(@s2_v1, :v1))
      assert Yex.Snapshot.equal?(live, other)
      refute Yex.Snapshot.equal?(live, decode!(@s1_v1, :v1))
    end

    test "structs holding bytes in yrs order from older y_ex are re-canonicalised" do
      # client 1 before client 5, one order y_ex 0.13.0 and earlier could write @multi_v1 in
      old = %Yex.Snapshot{doc: nil, reference: <<2, 1, 1, 1, 1, 5, 1, 0, 1, 2, 1, 6, 5, 2>>}
      assert Yex.Snapshot.encode_v1(old) == {:ok, @multi_v1}
      assert Yex.Snapshot.equal?(old, decode!(@multi_v1, :v1))
      {:ok, live} = Yex.snapshot(doc_with(@update_b, 5))
      assert Yex.Snapshot.equal?(old, live)

      # state vector entries swapped, plus a clock-0 client
      swapped = %Yex.Snapshot{
        doc: nil,
        reference: <<2, 1, 1, 1, 1, 5, 1, 0, 1, 3, 5, 2, 1, 6, 9, 0>>
      }

      assert Yex.Snapshot.equal?(swapped, decode!(@multi_v1, :v1))
      assert Yex.Snapshot.equal?(swapped, old)
    end

    test "all snapshot functions work inside a transaction" do
      doc = doc_with(@update_a)

      Yex.Doc.transaction(doc, fn ->
        {:ok, snapshot} = Yex.snapshot(doc)
        assert {:ok, @s2_v1} = Yex.Snapshot.encode_v1(snapshot)
        assert {:ok, _} = Yex.Snapshot.encode_state_v1(decode!(@s1_v1, :v1), doc)
        text = Yex.Doc.get_text(doc, "text")
        assert [_ | _] = Yex.Text.to_delta(text, snapshot, decode!(@s1_v1, :v1))
      end)
    end
  end

  describe "encode_state with a detached snapshot" do
    test "restores the point-in-time state of any doc" do
      doc = doc_with(@update_a)

      for {encode, apply} <- [
            {&Yex.Snapshot.encode_state_v1/2, &Yex.apply_update_v1/2},
            {&Yex.Snapshot.encode_state_v2/2, &Yex.apply_update_v2/2}
          ] do
        {:ok, update} = encode.(decode!(@s1_v1, :v1), doc)
        restored = Yex.Doc.new()
        :ok = apply.(restored, update)
        assert Yex.Text.to_string(Yex.Doc.get_text(restored, "text")) == "abc"
      end
    end

    test "works on a doc missing a client's first blocks" do
      # yrs integrates an update whose first blocks for a client are missing behind a gap
      # and reports clock 0 for that client; encoding from a snapshot must not underflow.
      a = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      Yex.Text.insert(Yex.Doc.get_text(a, "x"), 0, "hello")
      {:ok, sv} = Yex.encode_state_vector(a)
      Yex.Text.insert(Yex.Doc.get_text(a, "y"), 0, "world")
      {:ok, later} = Yex.encode_state_as_update(a, sv)

      b = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 2, skip_gc: true})
      :ok = Yex.apply_update(b, later)
      snapshot = decode!(<<0, 1, 1, 10>>, :v1)

      assert {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot, b)
      assert {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot, b)
      assert {:ok, restored} = Yex.Snapshot.create_doc(snapshot, b)

      for {update, apply} <- [
            {update_v1, &Yex.apply_update_v1/2},
            {update_v2, &Yex.apply_update_v2/2}
          ] do
        target = Yex.Doc.new()
        :ok = apply.(target, update)
        assert Yex.Text.to_string(Yex.Doc.get_text(target, "y")) == ""
      end

      # the gapped client cannot be encoded from clock 0, so it is left out
      assert Yex.Text.to_string(Yex.Doc.get_text(restored, "y")) == ""
    end

    test "a snapshot clock inside a block encodes a valid update from a decoded snapshot" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      snapshot = mid_block_snapshot(doc, text)
      {:ok, bytes} = Yex.Snapshot.encode_v1(snapshot)
      detached = decode!(bytes, :v1)
      {:ok, state_vector} = Yex.encode_state_vector(doc)
      {:ok, _} = Yex.Doc.monitor_update(doc)
      {:ok, _} = Yex.Doc.monitor_transaction_cleanup(doc)

      for snapshot <- [snapshot, detached] do
        {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot, doc)
        {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot, doc)
        assert_restores(update_v1, &Yex.apply_update_v1/2, "Xabc")
        assert_restores(update_v2, &Yex.apply_update_v2/2, "Xabc")
      end

      assert {:ok, restored} = Yex.Snapshot.create_doc(detached, doc)
      assert Yex.Text.to_string(Yex.Doc.get_text(restored, "text")) == "Xabc"
      # the split leaves the content and state vector unchanged and emits no event
      refute_receive {:update_v1, _, _, _}, 50
      refute_receive {:transaction_cleanup, _, _, _}
      assert Yex.encode_state_vector(doc) == {:ok, state_vector}
      assert Yex.Text.to_string(text) == "XYabc"
      assert_monitors_live(doc, text)
    end

    test "encode_state_v1/1 raises for a detached snapshot" do
      assert_raise ArgumentError, fn -> Yex.Snapshot.encode_state_v1(decode!(@s1_v1, :v1)) end
      assert_raise ArgumentError, fn -> Yex.Snapshot.encode_state_v2(decode!(@s1_v1, :v1)) end
    end
  end

  describe "create_doc" do
    test "restores text as of the snapshot (yjs createDocFromSnapshot example)" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "world!")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 0, "hello ")

      assert {:ok, %Yex.Doc{} = restored} = Yex.Snapshot.create_doc(snapshot, doc)
      assert Yex.Text.to_string(Yex.Doc.get_text(restored, "text")) == "world!"
    end

    test "restores maps and arrays into a supplied doc" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      map = Yex.Doc.get_map(doc, "map")
      array = Yex.Doc.get_array(doc, "array")
      Yex.Map.set(map, "a", "one")
      Yex.Array.push(array, "x")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Map.set(map, "a", "two")
      Yex.Map.set(map, "b", "three")
      Yex.Array.delete(array, 0)

      target = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      assert {:ok, ^target} = Yex.Snapshot.create_doc(snapshot, doc, target)
      assert Yex.Map.to_map(Yex.Doc.get_map(target, "map")) == %{"a" => "one"}
      assert Yex.Array.to_list(Yex.Doc.get_array(target, "array")) == ["x"]
    end

    test "returns encoding_exception when the origin doc has gc enabled" do
      doc = Yex.Doc.new()
      {:ok, snapshot} = Yex.snapshot(doc)
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.create_doc(snapshot, doc)

      target = Yex.Doc.new()
      assert {:error, {:encoding_exception, _}} = Yex.Snapshot.create_doc(snapshot, doc, target)
      assert Yex.encode_state_vector(target) == {:ok, <<0>>}
    end
  end

  describe "Yex.Text.to_delta/3" do
    setup do
      doc = doc_with(@update_a)
      %{doc: doc, text: Yex.Doc.get_text(doc, "text")}
    end

    test "marks removed and added text like yjs toDelta(s2, s1)", %{text: text} do
      delta = Yex.Text.to_delta(text, decode!(@s2_v1, :v1), decode!(@s1_v2, :v2))

      assert delta == [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => ychange("removed", 1)}},
               %{insert: "c"},
               %{insert: "d", attributes: %{"bold" => true, "ychange" => ychange("added", 4)}}
             ]

      # without the y_ex "id" addition it is exactly the yjs output
      assert Enum.map(delta, fn
               %{attributes: %{"ychange" => y} = attrs} = op ->
                 %{op | attributes: %{attrs | "ychange" => Map.delete(y, "id")}}

               op ->
                 op
             end) ==
               [
                 %{insert: "a"},
                 %{insert: "b", attributes: %{"ychange" => %{"type" => "removed"}}},
                 %{insert: "c"},
                 %{insert: "d", attributes: %{"bold" => true, "ychange" => %{"type" => "added"}}}
               ]
    end

    test "shows the state at a single snapshot", %{text: text} do
      assert Yex.Text.to_delta(text, decode!(@s1_v1, :v1)) == [%{insert: "abc"}]
    end

    test "reversed snapshots match yjs toDelta(s1, s2)", %{text: text} do
      assert Yex.Text.to_delta(text, decode!(@s1_v1, :v1), decode!(@s2_v1, :v1)) == [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => ychange("added", 1)}},
               %{insert: "c"},
               %{insert: "d", attributes: %{"ychange" => ychange("removed", 4)}}
             ]
    end

    test "nil snapshots", %{doc: doc, text: text} do
      assert Yex.Text.to_delta(text, nil, nil) == Yex.Text.to_delta(text)
      {:ok, current} = Yex.snapshot(doc)
      s1 = decode!(@s1_v1, :v1)
      assert Yex.Text.to_delta(text, nil, s1) == Yex.Text.to_delta(text, current, s1)
    end

    test "has no side effects on the doc", %{doc: doc, text: text} do
      {:ok, before} = Yex.encode_state_as_update(doc)
      plain = Yex.Text.to_delta(text)
      {:ok, undo} = Yex.UndoManager.new(doc, text)
      {:ok, _} = Yex.Doc.monitor_update(doc)
      {:ok, _} = Yex.Doc.monitor_transaction_cleanup(doc)

      Yex.Text.to_delta(text, decode!(@s2_v1, :v1), decode!(@s1_v1, :v1))

      refute_receive {:update_v1, _, _, _}, 50
      refute_receive {:transaction_cleanup, _, _, _}
      refute Yex.UndoManager.can_undo?(undo)
      assert Yex.Text.to_delta(text) == plain
      assert Yex.encode_state_as_update(doc) == {:ok, before}
      assert_monitors_live(doc, text)
    end

    test "joins an open transaction, including its uncommitted changes", %{doc: doc, text: text} do
      Yex.Doc.transaction(doc, fn ->
        Yex.Text.insert(text, 0, "x")

        assert [%{insert: "x", attributes: %{"ychange" => %{"type" => "added"}}} | _] =
                 Yex.Text.to_delta(text, nil, decode!(@s2_v1, :v1))
      end)
    end

    test "raises on a gc-enabled doc unless both snapshots are nil" do
      doc = doc_with(@update_a, 1, false)
      text = Yex.Doc.get_text(doc, "text")
      assert_raise ArgumentError, fn -> Yex.Text.to_delta(text, decode!(@s1_v1, :v1)) end
      assert_raise ArgumentError, fn -> Yex.Text.to_delta(text, nil, decode!(@s1_v1, :v1)) end
      assert Yex.Text.to_delta(text, nil, nil) == Yex.Text.to_delta(text)
    end

    test "raises on a gc-enabled doc inside a transaction and leaves the doc usable" do
      doc = doc_with(@update_a, 1, false)
      text = Yex.Doc.get_text(doc, "text")

      Yex.Doc.transaction(doc, fn ->
        assert_raise ArgumentError, fn -> Yex.Text.to_delta(text, decode!(@s1_v1, :v1)) end
      end)

      Yex.Text.insert(text, 0, "x")
      assert Yex.Text.to_string(text) == "xacd"
    end

    test "raises on a gc-enabled doc when called from another process" do
      worker = start_supervised!(__MODULE__.Worker)
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: false}, worker)
      :ok = Yex.apply_update_v1(doc, @update_a)
      text = Yex.Doc.get_text(doc, "text")

      assert_raise ArgumentError, fn -> Yex.Text.to_delta(text, decode!(@s1_v1, :v1)) end
      assert Yex.Text.to_string(text) == "acd"
    end

    test "raises on a deleted text" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      map = Yex.Doc.get_map(doc, "map")
      Yex.Map.set(map, "t", Yex.TextPrelim.from("hi"))
      {:ok, text} = Yex.Map.fetch(map, "t")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Map.delete(map, "t")

      assert_raise Yex.DeletedSharedTypeError, fn -> Yex.Text.to_delta(text, snapshot) end
    end

    test "snapshots naming clients this doc has never seen do not crash", %{text: text} do
      # @multi_v1 deletes an item of client 5, which doc A does not have
      # once client 5 is dropped, @multi_v1 is @s2_v1 for this doc
      multi = decode!(@multi_v1, :v1)
      s1 = decode!(@s1_v1, :v1)

      assert Yex.Text.to_delta(text, multi, s1) == [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => ychange("removed", 1)}},
               %{insert: "c"},
               %{insert: "d", attributes: %{"bold" => true, "ychange" => ychange("added", 4)}}
             ]

      assert Yex.Text.to_delta(text, s1, multi) == [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => ychange("added", 1)}},
               %{insert: "c"},
               %{insert: "d", attributes: %{"ychange" => ychange("removed", 4)}}
             ]
    end

    test "a snapshot ahead of the doc does not crash" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "abc")

      # the local items carry the same ids as the yjs doc, so "b" shows as removed
      assert Yex.Text.to_delta(text, decode!(@s2_v1, :v1), decode!(@s1_v1, :v1)) == [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => ychange("removed", 1)}},
               %{insert: "c"}
             ]
    end

    test "embeds never carry a ychange" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      {:ok, s1} = Yex.snapshot(doc)
      Yex.Text.insert(text, 0, "ab")
      Yex.Text.insert_embed(text, 1, %{"image" => "x.png"})
      {:ok, s2} = Yex.snapshot(doc)

      assert [
               %{insert: "a", attributes: %{"ychange" => %{"type" => "added"}}},
               %{insert: %{"image" => "x.png"}} = embed,
               %{insert: "b", attributes: %{"ychange" => %{"type" => "added"}}}
             ] = Yex.Text.to_delta(text, s2, s1)

      refute Map.has_key?(embed, :attributes)
    end
  end

  describe "Yex.XmlText.to_delta/3" do
    test "marks removed and added text" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1, skip_gc: true})
      xml = Yex.Doc.get_xml_fragment(doc, "xml")
      Yex.XmlFragment.insert(xml, 0, Yex.XmlTextPrelim.from("abc"))
      {:ok, text} = Yex.XmlFragment.fetch(xml, 0)
      {:ok, s1} = Yex.snapshot(doc)
      Yex.XmlText.delete(text, 1, 1)
      Yex.XmlText.insert(text, 2, "d", %{"bold" => true})
      {:ok, s2} = Yex.snapshot(doc)

      assert [
               %{insert: "a"},
               %{insert: "b", attributes: %{"ychange" => %{"type" => "removed"}}},
               %{insert: "c"},
               %{insert: "d", attributes: %{"bold" => true, "ychange" => %{"type" => "added"}}}
             ] = Yex.XmlText.to_delta(text, s2, s1)

      assert Yex.XmlText.to_delta(text, s1) == [%{insert: "abc"}]
      assert Yex.XmlText.to_delta(text, nil, nil) == Yex.XmlText.to_delta(text)
    end

    test "raises on a gc-enabled doc" do
      doc = Yex.Doc.new()
      xml = Yex.Doc.get_xml_fragment(doc, "xml")
      Yex.XmlFragment.insert(xml, 0, Yex.XmlTextPrelim.from("abc"))
      {:ok, text} = Yex.XmlFragment.fetch(xml, 0)
      {:ok, snapshot} = Yex.snapshot(doc)
      assert_raise ArgumentError, fn -> Yex.XmlText.to_delta(text, snapshot) end
    end
  end
end
