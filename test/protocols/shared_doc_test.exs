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
            case Sync.read_sync_message(sync_message, doc, "#{inspect(proc)}") do
              :ok ->
                :ok

              {:ok, reply} ->
                send(proc, {:yjs, Sync.message_encode!({:sync, reply}), self()})
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

  test "will automatically shut down when there are no more observers" do
    docname = random_docname()

    {:ok, remote_shared_doc} =
      SharedDoc.start(doc_name: docname)

    Process.monitor(remote_shared_doc)

    SharedDoc.observe(remote_shared_doc)
    SharedDoc.unobserve(remote_shared_doc)

    assert_receive {:DOWN, _, :process, ^remote_shared_doc, _}
  end

  test "sync step1 message" do
    docname = random_docname()

    {:ok, remote_shared_doc} =
      SharedDoc.start(doc_name: docname)

    Task.async(fn ->
      doc = Doc.new()

      SharedDoc.observe(remote_shared_doc)
      # send sync step1 (remote to local sync)
      {:ok, step1} = Sync.get_sync_step1(doc)
      local_message = Yex.Sync.message_encode!({:sync, step1})
      SharedDoc.send_yjs_message(remote_shared_doc, local_message)

      # sync step2 message
      assert_receive {:yjs, <<0, 1>> <> _, ^remote_shared_doc}
    end)
    |> Task.await()
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

  describe "awareness" do
    test "send awareness message" do
      docname = random_docname()

      {:ok, shared_doc} =
        SharedDoc.start(doc_name: docname)

      SharedDoc.observe(shared_doc)

      {:ok, awareness} = Yex.Awareness.new(Yex.Doc.with_options(%Yex.Doc.Options{client_id: 10}))
      Yex.Awareness.set_local_state(awareness, %{"key" => "value"})
      {:ok, awareness_update} = Yex.Awareness.encode_update(awareness, [10])
      message = Sync.message_encode!({:awareness, awareness_update})
      SharedDoc.send_yjs_message(shared_doc, message)

      Task.async(fn ->
        doc = Doc.new()
        SharedDoc.observe(shared_doc)

        {:ok, step1} = Sync.get_sync_step1(doc)
        local_message = Yex.Sync.message_encode!({:sync, step1})
        SharedDoc.start_sync(shared_doc, local_message)
        # receive initial awareness message
        assert_receive {:yjs, <<1>> <> _, ^shared_doc}
      end)
      |> Task.await()
    end
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

          0
        end

        def update_v1(state, _update, _doc_name, _doc) do
          state + 1
        end

        def unbind(_state, _doc_name, doc) do
          case Yex.encode_state_as_update(doc) do
            {:ok, update} ->
              File.write!("test/managed/test_output_file", update, [:write, :binary])

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
      data = File.read!("test/managed/test_output_file")
      assert byte_size(data) > 0

      doc = Doc.new()
      assert :ok = Yex.apply_update(doc, data)
      localdata = Doc.get_array(doc, "array") |> Array.to_json()
      assert Enum.member?(localdata, "initial_data")
    end
  end
end
