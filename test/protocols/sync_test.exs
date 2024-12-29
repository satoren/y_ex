defmodule Yex.SyncTest do
  use ExUnit.Case
  alias Yex.{Doc, Sync, Array}
  doctest Yex.Sync

  describe "message_decode" do
    test "sync_step1" do
      {:ok, {:sync, {:sync_step1, <<0>>}}} = Sync.message_decode(<<0, 0, 1, 0>>)

      {:ok, {:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}}} =
        Sync.message_decode(<<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>)
    end

    test "sync_step2" do
      {:ok, {:sync, {:sync_step2, <<0>>}}} = Sync.message_decode(<<0, 1, 1, 0>>)
    end

    test "sync_update" do
      {:ok, {:sync, {:sync_update, <<0>>}}} = Sync.message_decode(<<0, 2, 1, 0>>)
    end

    test "auth" do
      {:ok, {:auth, "test"}} = Sync.message_decode(<<2, 0, 4, 116, 101, 115, 116>>)
    end

    test "query_awareness" do
      {:ok, :query_awareness} = Sync.message_decode(<<3>>)
    end

    test "awareness" do
      {:ok, {:awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>}} =
        Sync.message_decode(<<1, 10, 1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>)
    end

    test "custom" do
      {:ok, <<100, 7, 1, 2, 3, 4, 5, 6, 7>>} =
        Sync.message_encode({:custom, 100, <<1, 2, 3, 4, 5, 6, 7>>})
    end

    test "unexpected tag" do
      {:error, "Unexpected tag value: 5"} = Sync.message_decode(<<0, 5, 3, 0>>)

      assert_raise RuntimeError, fn ->
        Sync.message_decode!(<<0, 5, 3, 0>>)
      end
    end

    test "error" do
      {:error,
       {:encoding_exception,
        "while trying to read more data (expected: 10 bytes), an unexpected end of buffer was reached"}} =
        Sync.message_decode(<<0, 0, 10, 1, 217, 239, 244, 171, 5, 13>>)
    end

    test "message_decode!" do
      {:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}} =
        Sync.message_decode!(<<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>)

      assert_raise RuntimeError, fn ->
        Sync.message_decode!(<<0, 0, 10, 1, 217, 239, 244, 171, 5, 13>>)
      end
    end

    test "message_decode_v1" do
      {:ok, {:sync, {:sync_step1, <<0>>}}} = Sync.message_decode_v1(<<0, 0, 1, 0>>)
      {:ok, :query_awareness} = Sync.message_decode_v1(<<3>>)

      {:ok, {:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}}} =
        Sync.message_decode_v1(<<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>)
    end

    test "decode error" do
      {:error, {:encoding_exception, "failed to decode variable length integer"}} =
        Sync.message_decode_v2(<<0, 0, 1, 0>>)
    end
  end

  describe "message_encode" do
    test "sync_step1" do
      {:ok, <<0, 0, 1, 0>>} = Sync.message_encode({:sync, {:sync_step1, <<0>>}})
    end

    test "sync_step2" do
      {:ok, <<0, 1, 1, 0>>} = Sync.message_encode({:sync, {:sync_step2, <<0>>}})
    end

    test "sync_update" do
      {:ok, <<0, 2, 1, 0>>} = Sync.message_encode({:sync, {:sync_update, <<0>>}})
    end

    test "auth" do
      {:ok, <<2, 0, 4, 116, 101, 115, 116>>} = Sync.message_encode({:auth, "test"})
    end

    test "query_awareness" do
      {:ok, <<3>>} = Sync.message_encode(:query_awareness)
    end

    test "awareness" do
      {:ok, <<1, 10, 1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>} =
        Sync.message_encode({:awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>})
    end

    test "custom" do
      {:ok, <<100, 7, 1, 2, 3, 4, 5, 6, 7>>} =
        Sync.message_encode({:custom, 100, <<1, 2, 3, 4, 5, 6, 7>>})
    end

    test "message_encode" do
      {:ok, <<3>>} = Sync.message_encode(:query_awareness)

      {:ok, <<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>} =
        Sync.message_encode({:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}})
    end
  end

  describe "sync protocol operations" do
    setup do
      doc = Doc.new()
      {:ok, doc: doc}
    end

    test "get_update with binary input" do
      assert {:ok, {:sync_update, <<1, 2, 3>>}} = Sync.get_update(<<1, 2, 3>>)
    end

    test "get_update with invalid input" do
      assert_raise FunctionClauseError, fn ->
        Sync.get_update(123)
      end
    end

    test "read_sync_message with unknown message type", %{doc: doc} do
      assert {:error, :unknown_message} = Sync.read_sync_message({:unknown_type, <<>>}, doc, nil)
    end

    test "read_sync_message with sync_step1", %{doc: doc} do
      assert {:ok, {:sync_step2, _}} = Sync.read_sync_message({:sync_step1, <<0>>}, doc, nil)
    end

    test "read_sync_message with sync_step2", %{doc: doc} do
      assert :ok = Sync.read_sync_message({:sync_step2, <<0>>}, doc, nil)
    end

    test "read_sync_message with sync_update", %{doc: doc} do
      assert :ok = Sync.read_sync_message({:sync_update, <<0>>}, doc, nil)
    end
  end

  describe "sync protocol message encoding" do
    test "message_encode! with valid sync_step1" do
      encoded = Sync.message_encode!({:sync, {:sync_step1, <<0>>}})
      assert is_binary(encoded)
      assert byte_size(encoded) > 0
    end

    test "message_encode! with valid sync_step2" do
      encoded = Sync.message_encode!({:sync, {:sync_step2, <<0>>}})
      assert is_binary(encoded)
      assert byte_size(encoded) > 0
    end

    test "message_encode! with valid sync_update" do
      encoded = Sync.message_encode!({:sync, {:sync_update, <<0>>}})
      assert is_binary(encoded)
      assert byte_size(encoded) > 0
    end

    test "message_encode! with query_awareness" do
      encoded = Sync.message_encode!(:query_awareness)
      assert is_binary(encoded)
      assert byte_size(encoded) > 0
    end

    test "message_encode! with invalid message" do
      assert_raise RuntimeError, fn ->
        Sync.message_encode!({:invalid_type, :message})
      end
    end
  end

  describe "sync protocol message decoding" do
    test "message_decode! with valid sync_step1" do
      result = Sync.message_decode!(<<0, 0, 1, 0>>)
      assert {:sync, {:sync_step1, <<0>>}} = result
    end

    test "message_decode! with valid sync_step2" do
      result = Sync.message_decode!(<<0, 1, 1, 0>>)
      assert {:sync, {:sync_step2, <<0>>}} = result
    end

    test "message_decode! with valid sync_update" do
      result = Sync.message_decode!(<<0, 2, 1, 0>>)
      assert {:sync, {:sync_update, <<0>>}} = result
    end

    test "message_decode! with query_awareness" do
      result = Sync.message_decode!(<<3>>)
      assert :query_awareness = result
    end

    test "message_decode! with invalid message" do
      assert_raise RuntimeError, fn ->
        Sync.message_decode!(<<255, 255>>)
      end
    end

    test "message_decode handles various valid messages" do
      valid_messages = [
        {<<0, 0, 1, 0>>, {:sync, {:sync_step1, <<0>>}}},
        {<<0, 1, 1, 0>>, {:sync, {:sync_step2, <<0>>}}},
        {<<0, 2, 1, 0>>, {:sync, {:sync_update, <<0>>}}},
        {<<3>>, :query_awareness}
      ]

      Enum.each(valid_messages, fn {input, expected} ->
        assert {:ok, ^expected} = Sync.message_decode(input)
      end)
    end
  end

  describe "sync protocol v2 operations" do
    test "message_decode_v2 with valid message" do
      assert {:error, _} = Sync.message_decode_v2(<<0, 0, 1, 0>>)
    end

    test "message_encode_v2 with valid message" do
      assert {:ok, _} = Sync.message_encode_v2({:sync, {:sync_step1, <<0>>}})
    end
  end

  test "get_sync_step1" do
    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "a")

    assert {:ok, {:sync_step1, _sv}} = Sync.get_sync_step1(doc)
  end

  test "sync to remote" do
    remote_doc = Doc.new()

    Doc.get_array(remote_doc, "array")
    |> Array.insert(0, "a")

    local_doc = Doc.new()
    {:ok, local_message} = Sync.get_sync_step1(local_doc)

    {:ok, remote_message} = Sync.read_sync_message(local_message, remote_doc, "local_doc")

    :ok = Sync.read_sync_message(remote_message, local_doc, "remote_doc")

    assert ["a"] = Doc.get_array(local_doc, "array") |> Array.to_json()
  end

  test "sync to both" do
    remote_doc = Doc.new()

    Doc.get_array(remote_doc, "array")
    |> Array.insert(0, "remote")

    local_doc = Doc.new()

    Doc.get_array(local_doc, "array")
    |> Array.insert(0, "local")

    {:ok, local_message} = Sync.get_sync_step1(local_doc)
    {:ok, remote_message} = Sync.read_sync_message(local_message, remote_doc, "local_doc")
    :ok = Sync.read_sync_message(remote_message, local_doc, "remote_doc")

    {:ok, remote_message2} = Sync.get_sync_step1(remote_doc)
    {:ok, local_message2} = Sync.read_sync_message(remote_message2, local_doc, "remote_doc")
    :ok = Sync.read_sync_message(local_message2, remote_doc, "remote_doc")

    localdata = Doc.get_array(local_doc, "array") |> Array.to_json()
    remotedata = Doc.get_array(remote_doc, "array") |> Array.to_json()
    assert localdata == remotedata
    assert Enum.member?(localdata, "local")
    assert Enum.member?(localdata, "remote")
  end
end
