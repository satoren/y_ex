defmodule YexTest do
  use ExUnit.Case, async: true
  doctest Yex

  describe "apply_update" do
    test "apply_update" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update(doc1)
      {:ok, state2} = Yex.encode_state_as_update(doc2)
      :ok = Yex.apply_update(doc1, state2)
      :ok = Yex.apply_update(doc2, state1)
    end

    test "apply_update_v2" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update_v2(doc1)
      {:ok, state2} = Yex.encode_state_as_update_v2(doc2)
      :ok = Yex.apply_update_v2(doc1, state2)
      :ok = Yex.apply_update_v2(doc2, state1)
    end

    test "apply_update above dirty_cutoff" do
      doc1 = Yex.Doc.new()
      map1 = Yex.Doc.get_map(doc1, "m")

      Yex.Doc.transaction(doc1, fn ->
        for i <- 1..20_000, do: Yex.Map.set(map1, "k#{i}", i)
      end)

      {:ok, update} = Yex.encode_state_as_update(doc1)
      assert byte_size(update) > Yex.Nif.dirty_cutoff()

      doc2 = Yex.Doc.new()
      {:ok, _} = Yex.Doc.monitor_update(doc2)
      :ok = Yex.apply_update(doc2, update)

      assert map_size(Yex.Map.to_map(Yex.Doc.get_map(doc2, "m"))) == 20_000
      assert_receive {:update_v1, _, nil, ^doc2}
    end
  end

  describe "doc-sized calls above the dirty item limits" do
    setup do
      doc = Yex.Doc.new()
      map = Yex.Doc.get_map(doc, "m")
      array = Yex.Doc.get_array(doc, "a")
      items = Yex.Nif.dirty_encode_items() + 1

      Yex.Doc.transaction(doc, fn ->
        for i <- 1..items, do: Yex.Map.set(map, "k#{i}", i)
      end)

      # The item count is doc-wide: the map entries alone put the doc over both limits,
      # so the array declines too.
      Yex.Array.insert_list(array, 0, Enum.to_list(1..Yex.Nif.dirty_json_items()))
      %{doc: doc, map: map, array: array}
    end

    test "normal NIFs decline and the public functions use the dirty twins", %{
      doc: doc,
      map: map,
      array: array
    } do
      sv = <<0>>

      assert :dirty =
               Yex.Nif.encode_state_as_update_v1(doc, nil, nil, Yex.Nif.dirty_encode_items())

      assert :dirty =
               Yex.Nif.encode_state_as_update_v2(doc, nil, nil, Yex.Nif.dirty_encode_items())

      assert :dirty =
               Yex.Nif.encode_diff_and_state_vector_v1(doc, nil, sv, Yex.Nif.dirty_encode_items())

      assert :dirty =
               Yex.Nif.encode_sync_step1_response_v1(
                 doc,
                 nil,
                 <<1, 0>>,
                 nil,
                 Yex.Nif.dirty_encode_items()
               )

      assert :dirty = Yex.Nif.map_to_json(map, nil, Yex.Nif.dirty_json_items())
      assert :dirty = Yex.Nif.array_to_json(array, nil, Yex.Nif.dirty_json_items())

      assert Yex.encode_state_as_update_v1(doc) ==
               Yex.Nif.encode_state_as_update_v1(doc, nil, nil, nil)

      assert Yex.encode_state_as_update_v2(doc) ==
               Yex.Nif.encode_state_as_update_v2(doc, nil, nil, nil)

      assert Yex.encode_diff_and_state_vector_v1(doc, sv) ==
               Yex.Nif.encode_diff_and_state_vector_v1(doc, nil, sv, nil)

      assert Yex.Map.to_json(map) == Yex.Nif.map_to_json(map, nil, nil)
      assert Yex.Array.to_json(array) == Yex.Nif.array_to_json(array, nil, nil)
    end

    test "the dirty twins read the open transaction", %{doc: doc, map: map} do
      Yex.Doc.transaction(doc, fn ->
        Yex.Map.set(map, "inside", true)
        assert %{"inside" => true} = Yex.Map.to_json(map)

        {:ok, update} = Yex.encode_state_as_update_v1(doc)
        other = Yex.Doc.new()
        :ok = Yex.apply_update_v1(other, update)
        assert {:ok, true} = Yex.Map.fetch(Yex.Doc.get_map(other, "m"), "inside")
      end)
    end
  end

  describe "merge_updates" do
    test "merge_updates_v1" do
      doc1 = Yex.Doc.new()
      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update(doc1)
      {:ok, state2} = Yex.encode_state_as_update(doc2)
      {:ok, merged} = Yex.merge_updates_v1([state1, state2])
      assert {:ok, ^merged} = Yex.merge_updates([state1, state2])

      doc3 = Yex.Doc.new()
      text3 = Yex.Doc.get_text(doc3, "text")
      :ok = Yex.apply_update_v1(doc3, merged)

      assert Yex.Text.to_string(text3) == "Hello"
    end

    test "merge_updates_v2" do
      doc1 = Yex.Doc.new()
      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update_v2(doc1)
      {:ok, state2} = Yex.encode_state_as_update_v2(doc2)
      {:ok, merged} = Yex.merge_updates_v2([state1, state2])

      doc3 = Yex.Doc.new()
      text3 = Yex.Doc.get_text(doc3, "text")
      :ok = Yex.apply_update_v2(doc3, merged)

      assert Yex.Text.to_string(text3) == "Hello"
    end
  end

  describe "update_debug" do
    test "update_debug_v1" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "Hello")

      {:ok, update} = Yex.encode_state_as_update_v1(doc)
      {:ok, debug} = Yex.update_debug_v1(update)

      assert is_binary(debug)
      assert String.length(debug) > 0
      assert {:error, {:encoding_exception, _}} = Yex.update_debug_v1(<<1, 2, 3>>)
    end

    test "update_debug_v2" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "Hello")

      {:ok, update} = Yex.encode_state_as_update_v2(doc)
      {:ok, debug} = Yex.update_debug_v2(update)

      assert is_binary(debug)
      assert String.length(debug) > 0
      assert {:error, {:encoding_exception, _}} = Yex.update_debug_v2(<<1, 2, 3>>)
    end
  end

  describe "malformed v2 input" do
    # A truncated length varint at the end of a v2 update makes yrs index past the
    # input (DecoderV2::read_usize); these must come back as encoding errors.
    @truncated_v2 [<<0, 128>>, <<255, 255, 255>>]

    # A valid 16_390 byte first column, then a truncated varint: decoding panics at
    # the last byte, and the input is above Yex.Nif.dirty_cutoff().
    @oversized_truncated_v2 <<0, 134, 128, 1>> <> :binary.copy(<<0>>, 16_390) <> <<128>>

    test "apply_update_v2 returns an encoding error" do
      doc = Yex.Doc.new()

      for update <- @truncated_v2 do
        assert {:error, {:encoding_exception, _}} = Yex.apply_update_v2(doc, update)
      end
    end

    test "apply_update_v2 above the dirty cutoff returns an encoding error" do
      assert byte_size(@oversized_truncated_v2) > Yex.Nif.dirty_cutoff()
      doc = Yex.Doc.new()

      assert {:error, {:encoding_exception, _}} =
               Yex.apply_update_v2(doc, @oversized_truncated_v2)
    end

    test "apply_update_v2 inside a transaction returns an encoding error" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")

      Yex.Doc.transaction(doc, fn ->
        Yex.Text.insert(text, 0, "a")
        assert {:error, {:encoding_exception, _}} = Yex.apply_update_v2(doc, <<0, 128>>)
        Yex.Text.insert(text, 1, "b")
      end)

      assert Yex.Text.to_string(text) == "ab"
    end

    test "merge_updates_v2 returns an encoding error" do
      for update <- @truncated_v2 do
        assert {:error, {:encoding_exception, _}} = Yex.merge_updates_v2([update])
      end

      {:ok, valid} = Yex.encode_state_as_update_v2(Yex.Doc.new())
      assert {:error, {:encoding_exception, _}} = Yex.merge_updates_v2([valid, <<0, 128>>])
    end

    test "merge_updates_v2 output on valid input is unchanged" do
      # Bytes from yrs::merge_updates_v2 before decoding moved into y_ex.
      u1 = Base.decode16!("000001010000010407047461626301030101000001010000")
      u2 = Base.decode16!("000001020000012805026D6B4100010100010101010077017600")

      merged =
        Base.decode16!("00000202010000032800040A066D6B746162634101030101000101020100770176010000")

      assert {:ok, ^merged} = Yex.merge_updates_v2([u1, u2])
      assert {:ok, ^merged} = Yex.Nif.merge_updates_v2_dirty([u1, u2])
    end

    test "merge_updates_v2 above the dirty cutoff returns an encoding error" do
      assert {:error, {:encoding_exception, _}} =
               Yex.merge_updates_v2([@oversized_truncated_v2])
    end

    test "update_debug_v2 returns an encoding error" do
      for update <- @truncated_v2 do
        assert {:error, {:encoding_exception, _}} = Yex.update_debug_v2(update)
      end
    end

    test "encode_state_as_update_v2 with a malformed state vector returns an encoding error" do
      doc = Yex.Doc.new()

      for sv <- @truncated_v2 do
        assert {:error, {:encoding_exception, _}} = Yex.encode_state_as_update_v2(doc, sv)
      end
    end
  end

  describe "malformed-but-decodable update that panics on apply" do
    # A v1 update carrying a WeakLink whose quoted range points past the referenced
    # block's content. It decodes cleanly, but applying it makes yrs panic in
    # ItemContent::splice (y-crdt/y-crdt#733). The NIF catches the panic and returns an
    # encoding error instead of crashing the caller.
    @weak_link_apply_panic_v1 <<1, 18, 1, 0, 4, 1, 1, 116, 1, 104, 132, 1, 0, 1, 101, 129, 1, 1,
                                2, 129, 1, 3, 1, 132, 1, 4, 6, 32, 119, 111, 114, 108, 100, 198,
                                1, 0, 1, 1, 4, 98, 111, 108, 100, 4, 116, 114, 117, 101, 198, 1,
                                3, 1, 4, 4, 98, 111, 108, 100, 4, 110, 117, 108, 108, 1, 1, 1, 97,
                                1, 136, 1, 13, 2, 125, 2, 125, 3, 199, 1, 13, 1, 14, 1, 40, 0, 1,
                                16, 1, 107, 1, 119, 1, 118, 39, 1, 1, 111, 1, 97, 0, 39, 1, 1, 109,
                                4, 108, 105, 110, 107, 7, 1, 1, 15, 1, 14, 39, 1, 1, 109, 2, 4, 7,
                                1, 1, 120, 3, 1, 112, 7, 0, 1, 21, 6, 4, 0, 1, 22, 3, 97, 98, 99,
                                41, 1, 1, 109, 3, 100, 111, 99, 36, 57, 48, 99, 51, 52, 54, 54, 99,
                                45, 56, 50, 54, 49, 45, 52, 56, 54, 98, 45, 57, 101, 57, 51, 45,
                                100, 56, 55, 98, 50, 57, 52, 98, 99, 53, 51, 100, 118, 4, 2, 103,
                                99, 120, 8, 101, 110, 99, 111, 100, 105, 110, 103, 125, 1, 8, 97,
                                117, 116, 111, 76, 111, 97, 100, 121, 10, 115, 104, 111, 117, 108,
                                100, 76, 111, 97, 100, 120, 1, 1, 2, 2, 3, 13, 1>>

    test "apply_update_v1 returns an encoding error instead of crashing" do
      doc = Yex.Doc.new()
      assert {:error, {:encoding_exception, _}} = Yex.apply_update(doc, @weak_link_apply_panic_v1)
    end

    test "the document stays usable after a caught apply panic" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "hello")

      assert {:error, {:encoding_exception, _}} = Yex.apply_update(doc, @weak_link_apply_panic_v1)

      # The doc is still readable and writable.
      assert {:ok, _} = Yex.encode_state_as_update(doc)
      Yex.Text.insert(text, 0, "X")
      assert Yex.Text.to_string(text) == "Xhello"
    end

    test "apply inside a transaction returns an encoding error and the transaction commits" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")

      Yex.Doc.transaction(doc, fn ->
        Yex.Text.insert(text, 0, "a")
        assert {:error, {:encoding_exception, _}} = Yex.apply_update(doc, @weak_link_apply_panic_v1)
        Yex.Text.insert(text, 1, "b")
      end)

      assert Yex.Text.to_string(text) == "ab"
    end
  end

  describe "encode_state_as_update" do
    test "encode_state_as_update" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update(doc)
    end

    test "encode_state_as_update!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_as_update!(doc))

      assert_raise ArgumentError, fn -> Yex.encode_state_as_update!(doc, <<11>>) end
    end

    test "encode_state_as_update_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update_v2(doc)
    end

    test "encode_diff_and_state_vector_v1 matches separate encode calls" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "t")
      Yex.Text.insert(text, 0, "abc")
      {:ok, remote_sv} = Yex.encode_state_vector(Yex.Doc.new())

      {:ok, diff, sv} = Yex.encode_diff_and_state_vector_v1(doc, remote_sv)
      {:ok, diff2} = Yex.encode_state_as_update(doc, remote_sv)
      {:ok, sv2} = Yex.encode_state_vector(doc)

      assert diff == diff2
      assert sv == sv2
    end
  end

  describe "encode_state_vector" do
    test "encode_state_vector" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector(doc)
    end

    test "encode_state_vector!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_vector!(doc))
    end

    test "encode_state_vector_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector_v2(doc)
    end
  end

  describe "get_pending_update / get_pending_ds" do
    test "report the same pending state as Yex.Doc" do
      doc1 = Yex.Doc.new()
      text = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text, 0, "Hello")
      {:ok, sv} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 5, " World")
      Yex.Text.delete(text, 0, 5)
      {:ok, gapped} = Yex.encode_state_as_update(doc1, sv)

      doc2 = Yex.Doc.new()
      :ok = Yex.apply_update(doc2, gapped)

      assert {:ok, update} = Yex.get_pending_update(doc2)
      assert is_binary(update)
      assert {:ok, update} == Yex.Doc.get_pending_update(doc2)

      assert {:ok, ds} = Yex.get_pending_ds(doc2)
      assert is_binary(ds)
      assert {:ok, ds} == Yex.Doc.get_pending_ds(doc2)
    end
  end
end
