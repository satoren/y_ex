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
    for _ <- 1..10,
        into: "",
        do:
          Enum.random([
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "a",
            "b",
            "c",
            "d",
            "e",
            "f"
          ])
  end

  defp receive_and_handle_reply_with_timeout(doc, timeout \\ 10) do
    receive do
      {:yjs, reply, proc} ->
        case Yex.Sync.message_decode(reply) do
          {:ok, {:sync, sync_message}} ->
            case Sync.read_sync_message(sync_message, doc, proc) do
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

  describe "override option" do
    defmodule TestPersistence do
      @behaviour Yex.Managed.SharedDoc.PersistenceBehaviour

      def bind(state, _doc_name, doc) do
        Doc.get_array(doc, "array")
        |> Array.insert(0, "initial_data")

        state
      end

      def unbind(state, doc_name, doc) do
        case Yex.encode_state_as_update(doc) do
          {:ok, update} ->
            File.write!(Path.join(state.out_dir, doc_name), update, [:write, :binary])

          _ ->
            []
        end

        :ok
      end

      def update_v1(state, _update, _doc_name, _doc) do
        state
      end
    end

    @tag :tmp_dir
    test "persistence and arg", %{tmp_dir: tmp_dir} do
      docname = random_docname()

      {:ok, remote_shared_doc} =
        SharedDocSupervisor.start_child(docname,
          persistence: {TestPersistence, %{out_dir: tmp_dir}},
          idle_timeout: 1
        )

      remote_shared_doc = GenServer.whereis(remote_shared_doc)
      Process.monitor(remote_shared_doc)

      assert_receive {:DOWN, _, :process, ^remote_shared_doc, _}

      # see TestPersistence.unbind/3
      persistence_data_path = Path.join(tmp_dir, docname)
      data = File.read!(persistence_data_path)
      assert byte_size(data) > 0
    end
  end
end
