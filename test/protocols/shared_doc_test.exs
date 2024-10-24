defmodule Yex.Sync.SharedDocTest do
  use ExUnit.Case
  alias Yex.{Doc, Array, Sync}
  alias Yex.Sync.SharedDoc

  setup_all do
    :ok
  end

  defp receive_and_handle_reply_with_timeout(doc, timeout \\ 10) do
    receive do
      {:yjs, reply, proc} ->
        case Sync.message_decode(reply) do
          {:ok, {:sync, sync_message}} ->
            case Sync.read_sync_message(sync_message, doc, proc) do
              :ok ->
                :ok

              {:ok, reply} ->
                SharedDoc.send_yjs_message(proc, Sync.message_encode!({:sync, reply}))
            end
        end

        receive_and_handle_reply_with_timeout(doc, timeout)
    after
      timeout -> :ok
    end
  end

  defp random_docname() do
    :crypto.strong_rand_bytes(10)
  end

  test "Observe SharedDoc on multiple clients, each of which will be synchronized" do
    docname = random_docname()
    {:ok, remote_shared_doc} = SharedDoc.start_link(doc_name: docname)

    client1 =
      Task.async(fn ->
        doc = Doc.new()

        Doc.get_array(doc, "array")
        |> Array.insert(0, "local")

        SharedDoc.observe(remote_shared_doc)
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
        doc = Doc.new()

        Doc.get_array(doc, "array")
        |> Array.insert(0, "local2")

        SharedDoc.observe(remote_shared_doc)
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

  test "Shut down when no client" do
    docname = random_docname()

    {:ok, remote_shared_doc} =
      SharedDoc.start(doc_name: docname)

    Process.monitor(remote_shared_doc)

    Task.async(fn ->
      doc = Doc.new()
      SharedDoc.observe(remote_shared_doc)

      {:ok, step1} = Sync.get_sync_step1(doc)
      local_message = Yex.Sync.message_encode!({:sync, step1})
      SharedDoc.start_sync(remote_shared_doc, local_message)
    end)
    |> Task.await()

    assert_receive {:DOWN, _, :process, ^remote_shared_doc, _}
  end

  describe "Persistence" do
    test "load initial data at bind" do
      defmodule PersistenceTest do
        @behaviour Yex.Managed.SharedDoc.PersistenceBehaviour

        def bind(_arg, _doc_name, doc) do
          Doc.get_array(doc, "array")
          |> Array.insert(0, "initial_data")

          []
        end

        def unbind(_state, _doc_name, _doc) do
          :ok
        end

        def update_v1(state, update, _doc_name, _doc) do
          [update | state]
        end
      end

      docname = random_docname()

      {:ok, remote_shared_doc} =
        SharedDoc.start(
          doc_name: docname,
          persistence: PersistenceTest
        )

      Task.async(fn ->
        doc = Doc.new()

        SharedDoc.observe(remote_shared_doc)

        {:ok, step1} = Sync.get_sync_step1(doc)
        local_message = Yex.Sync.message_encode!({:sync, step1})
        SharedDoc.start_sync(remote_shared_doc, local_message)

        receive_and_handle_reply_with_timeout(doc)
        localdata = Doc.get_array(doc, "array") |> Array.to_json()
        assert Enum.member?(localdata, "initial_data")
      end)
      |> Task.await()
    end

    test "save at unbind" do
      defmodule PersistenceFileWriteTest do
        @behaviour Yex.Managed.SharedDoc.PersistenceBehaviour

        def bind(_state, _doc_name, doc) do
          Doc.get_array(doc, "array")
          |> Array.insert(0, "initial_data")

          []
        end

        def unbind(_state, _doc_name, doc) do
          case Yex.encode_state_as_update(doc) do
            {:ok, update} ->
              File.mkdir_p!("tmp/test")
              File.write!("tmp/test/test_output_file", update, [:write, :binary])

            _ ->
              []
          end

          :ok
        end
      end

      docname = random_docname()

      {:ok, remote_shared_doc} =
        SharedDoc.start(
          doc_name: docname,
          persistence: PersistenceFileWriteTest
        )

      Task.async(fn ->
        doc = Doc.new()

        SharedDoc.observe(remote_shared_doc)
        {:ok, step1} = Sync.get_sync_step1(doc)
        local_message = Yex.Sync.message_encode!({:sync, step1})
        SharedDoc.start_sync(remote_shared_doc, local_message)

        receive_and_handle_reply_with_timeout(doc)
        localdata = Doc.get_array(doc, "array") |> Array.to_json()
        assert Enum.member?(localdata, "initial_data")
      end)
      |> Task.await()

      Process.monitor(remote_shared_doc)

      assert_receive {:DOWN, _, :process, ^remote_shared_doc, _}
      data = File.read!("tmp/test/test_output_file")
      assert byte_size(data) > 0

      doc = Doc.new()
      assert :ok = Yex.apply_update(doc, data)
      localdata = Doc.get_array(doc, "array") |> Array.to_json()
      assert Enum.member?(localdata, "initial_data")
    end
  end
end
