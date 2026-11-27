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

  defp wait_until(fun) do
    unless fun.() do
      Process.sleep(1)
      wait_until(fun)
    end
  end

  defp delayed_auto_exit(pid), do: :sys.get_state(pid).assigns.delayed_auto_exit

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

      refute_receive {:yjs, _, _pid}, 10
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

  describe "Persistence on shutdown" do
    defmodule PersistenceNotifyTest do
      @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

      def bind(test_pid, _doc_name, doc) do
        Doc.get_array(doc, "array") |> Array.insert(0, "data")
        test_pid
      end

      def unbind(test_pid, doc_name, doc) do
        {:ok, update} = Yex.encode_state_as_update(doc)
        send(test_pid, {:unbind, doc_name, update})
        :ok
      end
    end

    defp start_persisted(opts \\ []) do
      docname = random_docname()

      opts =
        Keyword.merge(
          [
            doc_name: docname,
            persistence: {PersistenceNotifyTest, self()},
            auto_exit: false,
            trap_exit: true
          ],
          opts
        )

      {docname, opts}
    end

    test "unbind is called when the supervisor shuts down" do
      {docname, opts} = start_persisted()
      {:ok, sup} = Supervisor.start_link([{SharedDoc, opts}], strategy: :one_for_one)

      :ok = Supervisor.stop(sup)

      assert_receive {:unbind, ^docname, update}, 1_000
      doc = Doc.new()
      :ok = Yex.apply_update(doc, update)
      assert Doc.get_array(doc, "array") |> Array.to_json() == ["data"]
    end

    test "unbind is called when the child is terminated by a DynamicSupervisor" do
      {docname, opts} = start_persisted()
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)
      {:ok, pid} = DynamicSupervisor.start_child(sup, {SharedDoc, opts})

      :ok = DynamicSupervisor.terminate_child(sup, pid)

      assert_receive {:unbind, ^docname, _update}, 1_000
    end

    @tag :capture_log
    test "a linked process exiting abnormally still stops it, and unbind is called" do
      {docname, opts} = start_persisted()
      {:ok, pid} = SharedDoc.start(opts)
      ref = Process.monitor(pid)

      spawn(fn ->
        Process.link(pid)
        exit(:crash)
      end)

      assert_receive {:unbind, ^docname, _update}, 1_000
      # The crash report is logged before the process exits.
      assert_receive {:DOWN, ^ref, :process, ^pid, :crash}, 5_000
    end

    test "with auto_exit, a linked observer exiting normally after unobserve does not cancel the exit" do
      {_docname, opts} = start_persisted(auto_exit: true)
      {:ok, pid} = SharedDoc.start(opts)
      ref = Process.monitor(pid)
      :ok = SharedDoc.observe(pid)
      test_pid = self()

      # The linked process exits normally right after the last observer left,
      # before the SharedDoc checks whether to exit.
      :sys.suspend(pid)
      Task.start(fn -> GenServer.call(pid, {:unobserve, test_pid}) end)
      wait_until(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)
      spawn(fn -> Process.link(pid) end)
      wait_until(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 2} end)
      :sys.resume(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end

    test "a linked process exiting normally does not stop it" do
      {docname, opts} = start_persisted()
      {:ok, pid} = SharedDoc.start(opts)

      spawn(fn -> Process.link(pid) end)
      Process.exit(pid, :normal)

      _ = :sys.get_state(pid)
      assert Process.alive?(pid)
      refute_received {:unbind, ^docname, _}

      GenServer.stop(pid)
      assert_receive {:unbind, ^docname, _update}, 1_000
    end

    test "without trap_exit, the supervisor shutdown does not call unbind" do
      {docname, opts} = start_persisted(trap_exit: false)
      {:ok, sup} = Supervisor.start_link([{SharedDoc, opts}], strategy: :one_for_one)

      :ok = Supervisor.stop(sup)

      refute_receive {:unbind, ^docname, _update}, 50
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

    test "update_doc returns an error and keeps the process alive when the function raises" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname())

      assert {:error, %RuntimeError{message: "boom"}} =
               SharedDoc.update_doc(pid, fn _doc -> raise "boom" end)

      assert {:error, {:throw, :oops}} = SharedDoc.update_doc(pid, fn _doc -> throw(:oops) end)

      assert Process.alive?(pid)

      :ok =
        SharedDoc.update_doc(pid, fn doc -> Doc.get_array(doc, "array") |> Array.push("ok") end)

      assert SharedDoc.get_doc(pid) |> Doc.get_array("array") |> Array.to_json() == ["ok"]
    end
  end

  describe "auto_exit" do
    test "stops when no process observes before auto_exit_timeout" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), auto_exit_timeout: 10)

      assert_receive {:EXIT, ^pid, :normal}, 1_000
    end

    test "keeps running when observed before auto_exit_timeout" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), auto_exit_timeout: 200)
      :ok = SharedDoc.observe(pid)

      Process.sleep(300)
      assert Process.alive?(pid)
    end

    test "keeps running without observers when auto_exit_timeout is :infinity" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), auto_exit_timeout: :infinity)

      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "keeps running without observers when auto_exit is false" do
      {:ok, pid} =
        SharedDoc.start_link(doc_name: random_docname(), auto_exit: false, auto_exit_timeout: 10)

      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "with auto_exit_delay, stops once the delay has passed without observers" do
      {:ok, pid} = SharedDoc.start(doc_name: random_docname(), auto_exit_delay: 100)
      ref = Process.monitor(pid)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)

      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 50
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "with auto_exit_delay, waits after the last observer process went down" do
      {:ok, pid} = SharedDoc.start(doc_name: random_docname(), auto_exit_delay: 100)
      ref = Process.monitor(pid)

      Task.async(fn -> SharedDoc.observe(pid) end) |> Task.await()

      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 50
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "with auto_exit_delay, an observer joining in the meantime cancels the exit" do
      {:ok, pid} = SharedDoc.start(doc_name: random_docname(), auto_exit_delay: 100)
      ref = Process.monitor(pid)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)
      :ok = SharedDoc.observe(pid)

      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 200
    end

    test "with auto_exit_delay, a new departure supersedes the previous delayed exit" do
      {:ok, pid} = SharedDoc.start(doc_name: random_docname(), auto_exit_delay: 100)
      ref = Process.monitor(pid)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)
      first_exit = delayed_auto_exit(pid)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)

      # The timer of the first departure fires: it is ignored.
      send(pid, {{SharedDoc, :delayed_auto_exit}, first_exit})
      _ = :sys.get_state(pid)
      refute_received {:DOWN, ^ref, :process, ^pid, _}

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "with auto_exit_delay, a duplicate departure does not restart the delay" do
      {:ok, pid} = SharedDoc.start(doc_name: random_docname(), auto_exit_delay: 100)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)
      pending_exit = delayed_auto_exit(pid)
      :ok = SharedDoc.unobserve(pid)

      assert delayed_auto_exit(pid) == pending_exit
    end

    test "with auto_exit_delay, the initial auto_exit_timeout check does not cut the delay" do
      {:ok, pid} =
        SharedDoc.start(doc_name: random_docname(), auto_exit_timeout: 10, auto_exit_delay: 100)

      ref = Process.monitor(pid)
      :ok = SharedDoc.observe(pid)
      :ok = SharedDoc.unobserve(pid)

      # The initial check fires while the delayed exit is pending: it is ignored.
      send(pid, {SharedDoc, :auto_exit_check})
      _ = :sys.get_state(pid)
      refute_received {:DOWN, ^ref, :process, ^pid, _}

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  describe "awareness_throttle" do
    # Sends `count` awareness updates of one client from another process, so
    # that the calling process, observing, receives the broadcasts.
    defp send_awareness_updates(pid, count) do
      # The updates all reach the mailbox before the first one opens the
      # window, so they fall in it however slow the machine is.
      Task.async(fn -> while_suspended(pid, fn -> send_cursors(pid, count) end) end)
      |> Task.await()
    end

    defp send_cursors(pid, count) do
      {:ok, awareness} = Awareness.new(Doc.new())
      for n <- 1..count, do: send_awareness_update(pid, awareness, "#{n}")
    end

    defp send_awareness_update(pid, awareness, cursor) do
      Awareness.set_local_state(awareness, %{"cursor" => cursor})
      {:ok, update} = Awareness.encode_update(awareness, [Awareness.client_id(awareness)])
      SharedDoc.send_yjs_message(pid, Sync.message_encode!({:awareness, update}))
    end

    defp while_suspended(pid, fun) do
      :sys.suspend(pid)

      try do
        fun.()
      after
        :sys.resume(pid)
      end
    end

    defp cursors(message) do
      {:ok, observer} = Awareness.new(Doc.new())
      Awareness.apply_update(observer, elem(Sync.message_decode!(message), 1))
      observer |> Awareness.get_states() |> Map.values() |> Enum.map(& &1["cursor"])
    end

    defp receive_awareness_broadcasts(timeout) do
      receive do
        {:yjs, message, _proc} ->
          case Sync.message_decode(message) do
            {:ok, {:awareness, _}} -> [message | receive_awareness_broadcasts(timeout)]
            _ -> receive_awareness_broadcasts(timeout)
          end
      after
        timeout -> []
      end
    end

    # Waits for the next awareness broadcast, however slow the machine is.
    defp receive_awareness_broadcast(timeout \\ 1_000) do
      receive do
        {:yjs, message, _proc} ->
          case Sync.message_decode(message) do
            {:ok, {:awareness, _}} -> message
            _ -> receive_awareness_broadcast(timeout)
          end
      after
        timeout -> flunk("no awareness broadcast received")
      end
    end

    test "broadcasts the first update, then the updates of the window together" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), awareness_throttle: 100)
      :ok = SharedDoc.observe(pid)

      send_awareness_updates(pid, 3)
      first = receive_awareness_broadcast()
      _last = receive_awareness_broadcast()
      assert receive_awareness_broadcasts(100) == []

      # The first broadcast carries only the first update.
      assert cursors(first) == ["1"]
    end

    test "broadcasts the latest state at the end of the window" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), awareness_throttle: 100)
      :ok = SharedDoc.observe(pid)

      send_awareness_updates(pid, 3)
      _first = receive_awareness_broadcast()
      last = receive_awareness_broadcast()
      assert receive_awareness_broadcasts(100) == []

      assert cursors(last) == ["3"]
    end

    test "the window's only origin does not receive its own updates back" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname(), awareness_throttle: 100)
      :ok = SharedDoc.observe(pid)

      test_pid = self()

      # Another observer, the only origin of the window's updates.
      task =
        Task.async(fn ->
          :ok = SharedDoc.observe(pid)
          send(test_pid, :observing)
          {:ok, awareness} = Awareness.new(Doc.new())

          receive do
            :go ->
              send_awareness_update(pid, awareness, "1")
              send_awareness_update(pid, awareness, "2")
              send(test_pid, :sent)
          end

          receive_awareness_broadcasts(300)
        end)

      assert_receive :observing, 1_000

      # The test process opens the window, and the task's updates reach the
      # mailbox before it is processed, so they fall in the window.
      {:ok, awareness} = Awareness.new(Doc.new())

      while_suspended(pid, fn ->
        send_awareness_update(pid, awareness, "0")
        send(task.pid, :go)
        assert_receive :sent, 1_000
      end)

      # The task only got the update opening the window, not its own back.
      assert task |> Task.await() |> Enum.map(&cursors/1) == [["0"]]
      # The test process got the window's updates.
      assert cursors(receive_awareness_broadcast()) == ["2"]
    end

    test "broadcasts every update without awareness_throttle" do
      {:ok, pid} = SharedDoc.start_link(doc_name: random_docname())
      :ok = SharedDoc.observe(pid)

      send_awareness_updates(pid, 3)

      for _ <- 1..3, do: receive_awareness_broadcast()
      assert receive_awareness_broadcasts(100) == []
    end
  end
end
