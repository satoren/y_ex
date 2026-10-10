defmodule Yex.UpdateUtilsTest do
  use ExUnit.Case, async: true

  # Fixtures produced by yjs 13.6.30, client ids fixed:
  #
  #   const d1 = new Y.Doc(); d1.clientID = 1
  #   const d2 = new Y.Doc(); d2.clientID = 2
  #   const t1 = d1.getText('t'); t1.insert(0, 'abc')
  #   const svA = Y.encodeStateVector(d1)
  #   t1.insert(3, 'def'); t1.delete(1, 1)
  #   d2.getMap('m').set('k', 'v')
  #   Y.applyUpdate(d1, Y.encodeStateAsUpdate(d2))
  #   u1 = Y.encodeStateAsUpdate(d1); u2 = Y.encodeStateAsUpdateV2(d1)
  #   diff1 = Y.diffUpdate(u1, svA); diff2 = Y.diffUpdateV2(u2, svA)
  #   conv12 = Y.convertUpdateFormatV1ToV2(u1); conv21 = Y.convertUpdateFormatV2ToV1(u2)
  #
  # gap: client 1 inserts 'abc', then 'xy' encoded against the state vector after 'abc'.
  # merged_gap: Y.mergeUpdates([encodeStateAsUpdate(d2), gap]).
  # skip: Y.mergeUpdates of client 1 clocks 0..3 ('abc') and 5..7 ('pq'), leaving a Skip.
  # split: one item 'abcXYpq' from client 1; split_diff = Y.diffUpdate(split, {1 => 4}).
  # fmt_v2: t.insert(0, 'abc', {bold: true}); t.format(0, 2, {italic: true}), v2 encoded.
  # diff_partial = Y.diffUpdate(u1, {1 => 3, 2 => 1}).
  # gc: m.set('k', new Y.Text('hello')); m.delete('k'); the text's content is a GC struct.
  @u1 Base.decode16!(
        "020102002801016D016B017701760301000401017401618101000184010104636465660101010101"
      )
  @u2 Base.decode16!(
        "0000030241010200020007280004008100840C086D6B74616364656641020401010002410002010077017603000101010100"
      )
  @sv_a Base.decode16!("010103")
  @diff1 Base.decode16!("020102002801016D016B01770176010103840102036465660101010101")
  @diff2 Base.decode16!(
           "0000030241000104000328008409056D6B646566410003010100010102010077017601030101010100"
         )
  @gap Base.decode16!("0101010384010202787900")
  @merged_gap Base.decode16!("020102002801016D016B0177017601010384010202787900")
  @skip Base.decode16!("0103010004010174036162630A0284010402707100")
  @split Base.decode16!("0101010004010174076162635859707100")
  @split_diff Base.decode16!("010101048401030359707100")
  @fmt_v2 Base.decode16!(
            "00030003010241050400040242020006090600840186004600C6201874626F6C64616263626F6C646974616C69636974616C69630104020104460001010000010600787E787E00"
          )
  @diff_partial Base.decode16!("01010103840102036465660101010101")
  @gc Base.decode16!("010201002101016D016B0100050101010006")

  defp text_doc(client_id, content) do
    doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: client_id})
    Yex.Text.insert(Yex.Doc.get_text(doc, "t"), 0, content)
    doc
  end

  defp text_of(update, apply \\ &Yex.apply_update_v1/2) do
    doc = Yex.Doc.new()
    :ok = apply.(doc, update)
    Yex.Text.to_string(Yex.Doc.get_text(doc, "t"))
  end

  describe "diff_update" do
    test "matches yjs diffUpdate byte for byte" do
      assert {:ok, @diff1} = Yex.diff_update_v1(@u1, @sv_a)
      assert {:ok, @diff1} = Yex.diff_update(@u1, @sv_a)
    end

    test "matches yjs diffUpdateV2 byte for byte, reading a v1 state vector" do
      assert {:ok, @diff2} = Yex.diff_update_v2(@u2, @sv_a)
    end

    test "slices a block that the state vector splits" do
      assert {:ok, @split_diff} = Yex.diff_update_v1(@split, <<1, 1, 4>>)
    end

    test "leaves out clients the state vector already covers" do
      assert {:ok, @diff_partial} = Yex.diff_update_v1(@u1, <<2, 1, 3, 2, 1>>)
      {:ok, diff} = Yex.diff_update_v1(@u1, <<2, 1, 3, 2, 1>>)
      assert {:ok, %{from: %{1 => 3}, to: %{1 => 6}}} = Yex.parse_update_meta(diff)
    end

    test "brings a lagging doc up to date" do
      doc_a = text_doc(1, "Hello")
      {:ok, base} = Yex.encode_state_as_update_v1(doc_a)
      {:ok, sv_b} = Yex.encode_state_vector_v1(doc_a)
      Yex.Text.insert(Yex.Doc.get_text(doc_a, "t"), 5, " World")
      {:ok, full} = Yex.encode_state_as_update_v1(doc_a)

      {:ok, diff} = Yex.diff_update_v1(full, sv_b)
      assert byte_size(diff) < byte_size(full)

      doc_b = Yex.Doc.new()
      :ok = Yex.apply_update_v1(doc_b, base)
      :ok = Yex.apply_update_v1(doc_b, diff)
      assert Yex.Text.to_string(Yex.Doc.get_text(doc_b, "t")) == "Hello World"
    end

    test "an empty state vector returns the whole update" do
      {:ok, diff} = Yex.diff_update_v1(@u1, <<0>>)
      assert text_of(diff) == text_of(@u1)
      {:ok, diff2} = Yex.diff_update_v2(@u2, <<0>>)
      assert text_of(diff2, &Yex.apply_update_v2/2) == text_of(@u1)
    end

    test "a covering state vector returns no structs" do
      {:ok, sv} = Yex.encode_state_vector_from_update_v1(@u1)
      {:ok, diff} = Yex.diff_update_v1(@u1, sv)
      assert {:ok, %{from: from, to: to}} = Yex.parse_update_meta_v1(diff)
      assert from == %{} and to == %{}
    end

    test "a v2-framed state vector from encode_state_vector_v2 reads as empty" do
      doc = text_doc(1, "abc")
      {:ok, sv_v2} = Yex.encode_state_vector_v2(doc)
      {:ok, update} = Yex.encode_state_as_update_v2(doc)
      {:ok, diff} = Yex.diff_update_v2(update, sv_v2)
      assert text_of(diff, &Yex.apply_update_v2/2) == "abc"
    end

    test "keeps yrs behaviour for v2 bytes passed to the v1 form" do
      # Not rejected: yrs diff_updates_v1 decodes the column headers as v1 structs.
      assert {:ok, garbage} = Yex.diff_update_v1(@fmt_v2, <<0>>)
      assert garbage != @fmt_v2
      assert {:ok, <<0, 0>>} = Yex.diff_update_v1(@u2, <<0>>)
    end

    test "malformed input returns an encoding exception" do
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v1(<<1, 2, 3>>, <<0>>)
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v1(@u1, <<5, 1>>)
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v2(<<1, 2, 3>>, <<0>>)
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v2(@u2, <<5, 1>>)
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v2(@u1, <<0>>)
    end
  end

  describe "encode_state_vector_from_update" do
    test "matches yjs encodeStateVectorFromUpdate content" do
      assert {:ok, sv} = Yex.encode_state_vector_from_update_v1(@u1)
      assert {:ok, %{1 => 6, 2 => 1}} == Yex.decode_state_vector(sv)
      assert {:ok, ^sv} = Yex.encode_state_vector_from_update(@u1)
    end

    test "the v2 form reads a v2 update and returns a v1 state vector" do
      assert {:ok, sv} = Yex.encode_state_vector_from_update_v2(@u2)
      assert {:ok, %{1 => 6, 2 => 1}} == Yex.decode_state_vector(sv)
      assert {:ok, @diff2} = Yex.diff_update_v2(@u2, @sv_a)
    end

    test "agrees with the state vector of the doc the update came from" do
      doc = text_doc(7, "Hello")
      Yex.Map.set(Yex.Doc.get_map(doc, "m"), "k", 1)
      {:ok, update} = Yex.encode_state_as_update_v1(doc)
      {:ok, doc_sv} = Yex.encode_state_vector_v1(doc)
      {:ok, sv} = Yex.encode_state_vector_from_update_v1(update)
      assert Yex.decode_state_vector(sv) == Yex.decode_state_vector(doc_sv)
    end

    test "stops counting at a gap or a skip, as yjs does" do
      assert {:ok, <<0>>} = Yex.encode_state_vector_from_update_v1(@gap)
      assert {:ok, <<1, 1, 3>>} = Yex.encode_state_vector_from_update_v1(@skip)
    end

    test "the empty update has the empty state vector" do
      assert {:ok, <<0>>} = Yex.encode_state_vector_from_update_v1(<<0, 0>>)
      assert {:error, {:encoding_exception, _}} = Yex.encode_state_vector_from_update_v1(<<>>)
    end

    test "v2 bytes passed to the v1 form are rejected" do
      assert {:error, {:encoding_exception, _}} =
               Yex.encode_state_vector_from_update_v1(@fmt_v2)

      assert {:error, {:encoding_exception, _}} = Yex.encode_state_vector_from_update_v1(@u2)
    end
  end

  describe "convert_update_format" do
    test "matches yjs byte for byte in both directions" do
      assert {:ok, @u2} = Yex.convert_update_format_v1_to_v2(@u1)
      assert {:ok, @u1} = Yex.convert_update_format_v2_to_v1(@u2)
    end

    test "round trips a y_ex update and keeps its content" do
      doc = text_doc(3, "Hello")
      Yex.Text.format(Yex.Doc.get_text(doc, "t"), 0, 2, %{"bold" => true})
      {:ok, v1} = Yex.encode_state_as_update_v1(doc)
      {:ok, v2} = Yex.convert_update_format_v1_to_v2(v1)
      assert {:ok, ^v1} = Yex.convert_update_format_v2_to_v1(v2)
      assert text_of(v2, &Yex.apply_update_v2/2) == "Hello"
    end

    test "v2 bytes passed to the v1 form are rejected instead of becoming empty" do
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v1_to_v2(@u2)
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v1_to_v2(@fmt_v2)
    end

    test "malformed input returns an encoding exception" do
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v1_to_v2(<<1, 2, 3>>)
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v2_to_v1(<<1, 2, 3>>)
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v2_to_v1(@u1)
    end
  end

  describe "parse_update_meta" do
    test "matches yjs parseUpdateMeta for v1 and v2" do
      expected = %{from: %{1 => 0, 2 => 0}, to: %{1 => 6, 2 => 1}}
      assert {:ok, ^expected} = Yex.parse_update_meta(@u1)
      assert {:ok, ^expected} = Yex.parse_update_meta_v1(@u1)
      assert {:ok, ^expected} = Yex.parse_update_meta_v2(@u2)
    end

    test "counts garbage collected structs" do
      assert {:ok, debug} = Yex.update_debug_v1(@gc)
      assert debug =~ "gc("
      assert {:ok, %{from: %{1 => 0}, to: %{1 => 6}}} = Yex.parse_update_meta(@gc)
    end

    test "reports the range of an update with missing predecessors" do
      assert {:ok, %{from: %{1 => 3}, to: %{1 => 5}}} = Yex.parse_update_meta(@gap)

      assert {:ok, %{from: %{1 => 3, 2 => 0}, to: %{1 => 5, 2 => 1}}} =
               Yex.parse_update_meta(@merged_gap)
    end

    test "spans a skip" do
      assert {:ok, %{from: %{1 => 0}, to: %{1 => 7}}} = Yex.parse_update_meta(@skip)
    end

    test "an incremental update starts at the prior clock" do
      doc = text_doc(5, "abc")
      {:ok, _} = Yex.Doc.monitor_update(doc)
      Yex.Text.insert(Yex.Doc.get_text(doc, "t"), 3, "de")
      assert_receive {:update_v1, update, _, _}
      assert {:ok, %{from: %{5 => 3}, to: %{5 => 5}}} = Yex.parse_update_meta(update)
    end

    test "ignores the delete set" do
      doc = text_doc(5, "abc")
      {:ok, _} = Yex.Doc.monitor_update(doc)
      Yex.Text.delete(Yex.Doc.get_text(doc, "t"), 0, 1)
      assert_receive {:update_v1, update, _, _}
      assert {:ok, %{from: %{}, to: %{}}} = Yex.parse_update_meta(update)
    end

    test "keeps the largest client id" do
      client = 2 ** 53 - 1
      {:ok, update} = Yex.encode_state_as_update_v1(text_doc(client, "ab"))
      assert {:ok, %{from: %{^client => 0}, to: %{^client => 2}}} = Yex.parse_update_meta(update)
    end

    test "v2 bytes passed to the v1 form are rejected" do
      assert {:error, {:encoding_exception, _}} = Yex.parse_update_meta_v1(@fmt_v2)
      assert {:error, {:encoding_exception, _}} = Yex.parse_update_meta_v1(@u2)
      assert {:error, {:encoding_exception, _}} = Yex.parse_update_meta_v2(<<1, 2, 3>>)
    end
  end

  describe "decode_state_vector" do
    test "decodes a doc's state vector" do
      doc = text_doc(9, "Hello")
      assert {:ok, %{9 => 5}} = Yex.decode_state_vector(Yex.encode_state_vector!(doc))
    end

    test "edge cases" do
      assert {:ok, %{}} = Yex.decode_state_vector(<<0>>)
      assert {:error, {:encoding_exception, _}} = Yex.decode_state_vector(<<>>)
      assert {:error, {:encoding_exception, _}} = Yex.decode_state_vector(<<2, 1, 3>>)
    end
  end

  describe "above dirty_cutoff" do
    setup do
      doc = Yex.Doc.new()
      map = Yex.Doc.get_map(doc, "m")

      Yex.Doc.transaction(doc, fn ->
        for i <- 1..20_000, do: Yex.Map.set(map, "k#{i}", i)
      end)

      {:ok, v1} = Yex.encode_state_as_update_v1(doc)
      {:ok, v2} = Yex.encode_state_as_update_v2(doc)
      assert byte_size(v1) > Yex.Nif.dirty_cutoff()
      assert byte_size(v2) > Yex.Nif.dirty_cutoff()
      %{v1: v1, v2: v2}
    end

    test "the dirty twins return what the normal NIFs return", %{v1: v1, v2: v2} do
      assert Yex.diff_update_v1(v1, @sv_a) == Yex.Nif.diff_update_v1(v1, @sv_a)
      assert Yex.diff_update_v2(v2, @sv_a) == Yex.Nif.diff_update_v2(v2, @sv_a)

      assert Yex.encode_state_vector_from_update_v1(v1) ==
               Yex.Nif.encode_state_vector_from_update_v1(v1)

      assert Yex.encode_state_vector_from_update_v2(v2) ==
               Yex.Nif.encode_state_vector_from_update_v2(v2)

      assert Yex.convert_update_format_v1_to_v2(v1) == Yex.Nif.convert_update_format_v1_to_v2(v1)
      assert Yex.convert_update_format_v2_to_v1(v2) == Yex.Nif.convert_update_format_v2_to_v1(v2)
      assert Yex.parse_update_meta_v1(v1) == Yex.Nif.parse_update_meta_v1(v1)
      assert Yex.parse_update_meta_v2(v2) == Yex.Nif.parse_update_meta_v2(v2)
      assert {:ok, %{from: from}} = Yex.parse_update_meta_v1(v1)
      assert map_size(from) == 1
    end
  end

  test "runs inside an open transaction without touching it" do
    doc = text_doc(1, "abc")

    Yex.Doc.transaction(doc, fn ->
      assert {:ok, @diff1} = Yex.diff_update_v1(@u1, @sv_a)
      assert {:ok, %{from: %{1 => 0}}} = Yex.parse_update_meta(@u1)
    end)
  end

  describe "malformed v2 input" do
    # A truncated length varint at the end of a v2 update makes yrs index past the
    # input (DecoderV2::read_usize); these must come back as encoding errors.
    @truncated_v2 [<<0, 128>>, <<255, 255, 255>>]

    # A valid 16_390 byte first column, then a truncated varint: above
    # Yex.Nif.dirty_cutoff(), so the DirtyCpu twins decode it.
    @oversized_truncated_v2 <<0, 134, 128, 1>> <> :binary.copy(<<0>>, 16_390) <> <<128>>

    test "returns an encoding error from every v2 function" do
      for update <- @truncated_v2 do
        assert {:error, {:encoding_exception, _}} = Yex.diff_update_v2(update, @sv_a)
        assert {:error, {:encoding_exception, _}} = Yex.encode_state_vector_from_update_v2(update)
        assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v2_to_v1(update)
        assert {:error, {:encoding_exception, _}} = Yex.parse_update_meta_v2(update)
      end
    end

    test "returns an encoding error from the dirty twins" do
      update = @oversized_truncated_v2
      assert byte_size(update) > Yex.Nif.dirty_cutoff()
      assert {:error, {:encoding_exception, _}} = Yex.diff_update_v2(update, @sv_a)
      assert {:error, {:encoding_exception, _}} = Yex.encode_state_vector_from_update_v2(update)
      assert {:error, {:encoding_exception, _}} = Yex.convert_update_format_v2_to_v1(update)
      assert {:error, {:encoding_exception, _}} = Yex.parse_update_meta_v2(update)
    end
  end
end
