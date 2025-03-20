defmodule Yex.Sync.SharedDocTest do
  use ExUnit.Case
  alias Yex.{Doc, Array, Sync, Awareness}
  alias Yex.Sync.SharedDoc
  doctest SharedDoc

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

          _ ->
            :ok
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

  describe "observe/unobserve" do
    test "observe" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname())

      on_exit(fn ->
        Process.exit(pid, :normal)
      end)

      SharedDoc.observe(pid)

      doc = Doc.new()

      Doc.get_array(doc, "array")
      |> Array.insert(0, "local")

      assert {:ok, update} = Yex.encode_state_as_update(doc)

      DocServerTestModule.process_message_v1(
        pid,
        Sync.message_encode!({:sync, {:sync_step2, update}})
      )

      assert_receive {:yjs, _, pid}

      SharedDoc.unobserve(pid)

      Doc.get_array(doc, "array2")
      |> Array.insert(0, "1")

      assert {:ok, update} = Yex.encode_state_as_update(doc)

      DocServerTestModule.process_message_v1(
        pid,
        Sync.message_encode!({:sync, {:sync_step2, update}})
      )

      refute_receive {:yjs, _, _pid}
    end

    test "remove awareness when unobserve" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname())

      SharedDoc.observe(pid)

      Task.async(fn ->
        {:ok, awareness} = Yex.Awareness.new(Doc.new())
        Awareness.set_local_state(awareness, %{"key" => "value"})
        SharedDoc.observe(pid)

        {:ok, awareness_update} = Awareness.encode_update(awareness)

        SharedDoc.process_message_v1(
          pid,
          Sync.message_encode!({:awareness, awareness_update}),
          self()
        )
      end)
      |> Task.await()

      # added awareness
      {:ok, check_awareness} = Yex.Awareness.new(Doc.new())
      assert_receive {:yjs, message, _pid}
      {:awareness, message} = Sync.message_decode!(message)
      :ok = Awareness.apply_update(check_awareness, message)
      assert Awareness.get_client_ids(check_awareness) |> Enum.count() == 1

      # deleted awareness
      assert_receive {:yjs, message, _pid}
      {:awareness, message} = Sync.message_decode!(message)
      :ok = Awareness.apply_update(check_awareness, message)
      assert Awareness.get_client_ids(check_awareness) |> Enum.count() == 0
    end

    test "remove awareness" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname())
      SharedDoc.observe(pid)

      send_awareness = fn state ->
        {:ok, awareness} = Yex.Awareness.new(Doc.new())
        Awareness.set_local_state(awareness, state)
        SharedDoc.observe(pid)

        {:ok, awareness_update} = Awareness.encode_update(awareness)

        SharedDoc.process_message_v1(
          pid,
          Sync.message_encode!({:awareness, awareness_update}),
          self()
        )
      end

      send_awareness.(%{"key2" => "value2"})

      Task.async(fn ->
        send_awareness.(%{"key" => "value"})
        send_awareness.(%{"key" => "value"})
        send_awareness.(%{"key" => "value"})
      end)
      |> Task.await()

      {:ok, [message]} =
        SharedDoc.process_message_v1(
          pid,
          Sync.message_encode!(:query_awareness),
          self()
        )

      {:awareness, awareness_update} = Sync.message_decode!(message)

      {:ok, check_awareness} = Yex.Awareness.new(Doc.new())

      Awareness.apply_update(check_awareness, awareness_update)

      assert Awareness.get_client_ids(check_awareness) |> Enum.count() == 1
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

  describe "Document operations" do
    test "get_doc returns the current document state" do
      docname = random_docname()
      {:ok, pid} = SharedDoc.start_link(doc_name: docname)

      doc = Doc.new()

      Doc.get_array(doc, "array")
      |> Array.insert(0, "test_data")

      {:ok, update} = Yex.encode_state_as_update(doc)

      SharedDoc.process_message_v1(
        pid,
        Sync.message_encode!({:sync, {:sync_step2, update}}),
        self()
      )

      current_doc = SharedDoc.get_doc(pid)
      assert Doc.get_array(current_doc, "array") |> Array.to_json() == ["test_data"]
    end

    test "update_doc applies updates to the document" do
      docname = random_docname()
      {:ok, pid} = SharedDoc.start_link(doc_name: docname)

      doc = Doc.new()

      Doc.get_array(doc, "array")
      |> Array.insert(0, "initial_data")

      {:ok, update} = Yex.encode_state_as_update(doc)

      SharedDoc.process_message_v1(
        pid,
        Sync.message_encode!({:sync, {:sync_step2, update}}),
        self()
      )

      # Create a new update
      new_doc = Doc.new()

      Doc.get_array(new_doc, "array")
      |> Array.insert(0, "updated_data")

      {:ok, new_update} = Yex.encode_state_as_update(new_doc)
      :ok = SharedDoc.update_doc(pid, fn doc -> Yex.apply_update(doc, new_update) end)

      # Verify that the update was applied
      current_doc = SharedDoc.get_doc(pid)

      result = Doc.get_array(current_doc, "array") |> Array.to_json()
      assert Enum.member?(result, "initial_data")
      assert Enum.member?(result, "updated_data")
    end
  end
end
