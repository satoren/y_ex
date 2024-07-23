defmodule Yex.Managed.SharedDocSupervisorTest do
  use ExUnit.Case
  alias Yex.Sync
  alias Yex.Managed.{SharedDoc, SharedDocSupervisor}
  alias Yex.{Doc, Array}

  setup_all do
    start_link_supervised!(SharedDocSupervisor)
    :ok
  end

  defp random_docname() do
    :crypto.strong_rand_bytes(10)
  end

  defp receive_and_handle_reply_with_timeout(doc, timeout \\ 10) do
    receive do
      {:yjs, reply, proc} ->
        case Yex.Sync.message_decode(reply) do
          {:ok, {:sync, sync_message}} ->
            case Sync.read_sync_message(sync_message, doc, "#{inspect(proc)}") do
              :ok ->
                :ok

              {:ok, reply} ->
                send(proc, {:yjs, Yex.Sync.message_encode!({:sync, reply}), self()})
            end
        end

        receive_and_handle_reply_with_timeout(doc, timeout)
    after
      timeout -> :ok
    end
  end

  test "SharedDocs with the same document name will be sync" do
    docname = random_docname()

    client1 =
      Task.async(fn ->
        {:ok, remote_shared_doc} =
          SharedDocSupervisor.start_child(docname)

        doc = Doc.new()

        Doc.get_array(doc, "array")
        |> Array.insert(0, "local")

        SharedDocSupervisor.LocalPubsub.monitor(docname)
        {:ok, step1} = Sync.get_sync_step1(doc)
        local_message = Yex.Sync.message_encode!({:sync, step1})
        SharedDoc.start_sync(remote_shared_doc, local_message)

        receive_and_handle_reply_with_timeout(doc)

        localdata = Doc.get_array(doc, "array") |> Array.to_json()
        assert Enum.member?(localdata, "local")
        assert Enum.member?(localdata, "local2")
      end)

    client2 =
      Task.async(fn ->
        {:ok, remote_shared_doc} =
          SharedDocSupervisor.start_child(docname)

        doc = Doc.new()

        Doc.get_array(doc, "array")
        |> Array.insert(0, "local2")

        SharedDocSupervisor.LocalPubsub.monitor(docname)
        {:ok, step1} = Sync.get_sync_step1(doc)
        local_message = Yex.Sync.message_encode!({:sync, step1})
        SharedDoc.start_sync(remote_shared_doc, local_message)

        receive_and_handle_reply_with_timeout(doc)

        localdata = Doc.get_array(doc, "array") |> Array.to_json()
        assert Enum.member?(localdata, "local")
        assert Enum.member?(localdata, "local2")
      end)

    Task.await(client1)
    Task.await(client2)
  end
end
