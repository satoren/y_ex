defmodule Yex.SyncTest do
  use ExUnit.Case
  alias Yex.Sync
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
end
