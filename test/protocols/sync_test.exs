defmodule Yex.SyncTest do
  use ExUnit.Case
  alias Yex.{Doc, Sync, Array}
  doctest Yex.Sync

  test "message_decode" do
    {:ok, {:sync, {:sync_step1, <<0>>}}} = Sync.message_decode(<<0, 0, 1, 0>>)
    {:ok, :query_awareness} = Sync.message_decode(<<3>>)

    {:ok, {:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}}} =
      Sync.message_decode(<<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>)
  end

  test "message_encode" do
    {:ok, <<0, 0, 1, 0>>} = Sync.message_encode({:sync, {:sync_step1, <<0>>}})
    {:ok, <<3>>} = Sync.message_encode(:query_awareness)

    {:ok, <<0, 0, 7, 1, 217, 239, 244, 171, 5, 13>>} =
      Sync.message_encode({:sync, {:sync_step1, <<1, 217, 239, 244, 171, 5, 13>>}})
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
