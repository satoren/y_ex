defmodule DocServerTestModule do
  use Yex.DocServer
  require Logger
  alias Yex.Awareness
  alias Yex.Doc

  @impl true
  def init(_arg, %{doc: doc, awareness: awareness} = state) do
    Doc.get_array(doc, "array")
    |> Yex.Array.insert(0, "server data")

    Awareness.set_local_state(awareness, %{"name" => "remote test user"})

    {:ok, assign(state, :assigned_at_init, "value")}
  end

  @impl true
  def handle_call(:get_doc, _from, %{doc: doc} = state) do
    {:reply, doc, state}
  end

  @impl true
  def handle_call(:get_assigns, _from, %{doc: _doc, assigns: assigns} = state) do
    {:reply, assigns, state}
  end

  @impl true
  def handle_update_v1(doc, update, origin, state) do
    test_process = state.assigns[:test_process]

    if test_process != nil do
      send(test_process, {:doc_update, doc, update, origin})
    end

    {:noreply, state}
  end

  @impl true
  def handle_awareness_change(awareness, change, origin, state) do
    test_process = state.assigns[:test_process]

    if test_process != nil do
      send(test_process, {:awareness_change, awareness, change, origin})
    end

    {:noreply, state}
  end
end

defmodule DocServerHandleTestModule do
  use Yex.DocServer
  require Logger
  alias Yex.Doc

  @impl true
  def init(_arg, %{doc: doc} = state) do
    Doc.get_array(doc, "array")
    |> Yex.Array.insert(0, "server data")

    {:ok, assign(state, :assigned_at_init, "value")}
  end

  @impl true
  def handle_call(:custom_call, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:custom_cast, from}, state) do
    send(from, :custom_cast_reply)
    {:noreply, state}
  end

  @impl true
  def handle_info({:custom_message, from}, state) do
    send(from, :custom_message_reply)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end

defmodule DocServerWithoutAwarenessModule do
  use Yex.DocServer
  require Logger
  alias Yex.Doc

  @impl true
  def init(_arg, %{doc: doc, awareness: nil} = state) do
    Doc.get_array(doc, "array")
    |> Yex.Array.insert(0, "server data")

    {:ok, assign(state, :assigned_at_init, "value")}
  end

  @impl true
  def handle_call(:get_doc, _from, %{doc: doc} = state) do
    {:reply, doc, state}
  end

  @impl true
  def handle_call(:get_assigns, _from, %{doc: _doc, assigns: assigns} = state) do
    {:reply, assigns, state}
  end

  @impl true
  def handle_update_v1(doc, update, origin, state) do
    test_process = state.assigns[:test_process]

    if test_process != nil do
      send(test_process, {:doc_update, doc, update, origin})
    end

    {:noreply, state}
  end
end

defmodule Yex.DocServerTest do
  use ExUnit.Case
  alias Yex.{Array, Doc, Sync}
  import ExUnit.CaptureLog
  require Logger

  test "step1" do
    {:ok, pid} = DocServerTestModule.start_link([])

    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "local")

    assert {:ok, sv} = Yex.encode_state_vector(doc)

    assert {:ok, [<<0, 1>> <> _step2, <<0, 0>> <> _step1, <<1>> <> _awareness]} =
             DocServerTestModule.process_message_v1(
               pid,
               Sync.message_encode!({:sync, {:sync_step1, sv}})
             )
  end

  test "initial sync" do
    {:ok, pid} = DocServerTestModule.start_link([])

    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "local")

    assert {:ok, sv} = Yex.encode_state_vector(doc)

    assert {:ok, replies} =
             DocServerTestModule.process_message_v1(
               pid,
               Sync.message_encode!({:sync, {:sync_step1, sv}})
             )

    Enum.each(replies, fn reply ->
      case Sync.message_decode!(reply) do
        {:sync, {:sync_step2, update}} ->
          Yex.Doc.transaction(doc, fn ->
            Yex.apply_update(doc, update)
          end)

        {:sync, {:sync_step1, remote_sv}} ->
          {:ok, send_update} = Yex.encode_state_as_update(doc, remote_sv)

          assert :ok =
                   DocServerTestModule.process_message_v1(
                     pid,
                     Sync.message_encode!({:sync, {:sync_step2, send_update}}),
                     "test"
                   )

        {:awareness, _} ->
          :ok
      end
    end)

    merged_array = Doc.get_array(doc, "array") |> Array.to_json()
    assert Enum.member?(merged_array, "local")
    assert Enum.member?(merged_array, "server data")

    remote_doc = GenServer.call(pid, :get_doc)
    merged_array = Doc.get_array(remote_doc, "array") |> Array.to_json()
    assert Enum.member?(merged_array, "local")
    assert Enum.member?(merged_array, "server data")
  end

  test "handle_update" do
    {:ok, pid} = DocServerTestModule.start_link(assigns: %{test_process: self()})

    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "local")

    assert {:ok, sv} = Yex.encode_state_vector(doc)

    assert {:ok, replies} =
             DocServerTestModule.process_message_v1(
               pid,
               Sync.message_encode!({:sync, {:sync_step1, sv}})
             )

    Enum.each(replies, fn reply ->
      case Sync.message_decode!(reply) do
        {:sync, {:sync_step2, update}} ->
          Yex.Doc.transaction(doc, fn ->
            Yex.apply_update(doc, update)
          end)

        {:sync, {:sync_step1, remote_sv}} ->
          {:ok, send_update} = Yex.encode_state_as_update(doc, remote_sv)

          assert :ok =
                   DocServerTestModule.process_message_v1(
                     pid,
                     Sync.message_encode!({:sync, {:sync_step2, send_update}}),
                     "test"
                   )

        {:awareness, _} ->
          :ok
      end
    end)

    assert_receive {:doc_update, _remote_doc, _update, "test"}
  end

  test "handle_sync step 1 without awareness" do
    {:ok, pid} = DocServerWithoutAwarenessModule.start_link(assigns: %{test_process: self()})

    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "local")

    assert {:ok, sv} = Yex.encode_state_vector(doc)

    assert {:ok, [<<0, 1>> <> _step2, <<0, 0>> <> _step1]} =
             DocServerWithoutAwarenessModule.process_message_v1(
               pid,
               Sync.message_encode!({:sync, {:sync_step1, sv}})
             )

    assert_receive {:doc_update, _remote_doc, _update, nil}
  end

  test "assigns" do
    {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

    assert GenServer.call(pid, :get_assigns) == %{
             assigned_at_init: "value",
             initial_assigns_key: "value"
           }
  end

  describe "incvalid message" do
    test "invalid message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert {:error, _message} =
               DocServerTestModule.process_message_v1(
                 pid,
                 <<10>>
               )
    end

    test "invalid sync step 1 message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert {:error, _message} =
               DocServerTestModule.process_message_v1(
                 pid,
                 Sync.message_encode!({:sync, {:sync_step1, <<100>>}})
               )
    end

    test "invalid sync step 2 message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert capture_log(fn ->
               DocServerTestModule.process_message_v1(
                 pid,
                 Sync.message_encode!({:sync, {:sync_step2, <<200, 200, 200>>}})
               )

               Process.sleep(50)
             end) =~ "encoding_exception"
    end

    test "unknown message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert {:error, :unknown_message} =
               DocServerTestModule.process_message_v1(
                 pid,
                 <<10, 1, 200>>
               )
    end
  end

  describe "handle_custom messages" do
    test "custom_call" do
      {:ok, pid} = DocServerHandleTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert GenServer.call(pid, :custom_call) == :ok
    end

    test "custom_cast" do
      {:ok, pid} = DocServerHandleTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      assert GenServer.cast(pid, {:custom_cast, self()}) == :ok
      assert_receive :custom_cast_reply
    end

    test "custom_message" do
      {:ok, pid} = DocServerHandleTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      send(pid, {:custom_message, self()})
      assert_receive :custom_message_reply
    end

    test "terminate" do
      {:ok, pid} = DocServerHandleTestModule.start_link(assigns: %{initial_assigns_key: "value"})

      GenServer.stop(pid)
    end
  end

  describe "awareness" do
    test "awareness message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{test_process: self()})

      DocServerTestModule.process_message_v1(
        pid,
        Sync.message_encode!({:awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>}),
        "origin"
      )

      assert_receive {:awareness_change, _remote_doc, _update, "origin"}
    end

    test "query awareness message" do
      {:ok, pid} = DocServerTestModule.start_link(assigns: %{test_process: self()})

      assert <<3>> = Sync.message_encode!(:query_awareness)

      {:ok, [awareness_message]} =
        DocServerTestModule.process_message_v1(
          pid,
          Sync.message_encode!(:query_awareness),
          "origin"
        )

      assert {:awareness, msg} = Sync.message_decode!(awareness_message)
      {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      Yex.Awareness.apply_update(awareness, msg)

      assert {_, %{"name" => "remote test user"}} =
               Yex.Awareness.get_states(awareness) |> Enum.at(0)
    end

    test "no awareness" do
      {:ok, pid} = DocServerHandleTestModule.start_link(assigns: %{test_process: self()})

      DocServerHandleTestModule.process_message_v1(
        pid,
        Sync.message_encode!({:awareness, <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>}),
        "origin"
      )

      refute_receive _message
    end
  end
end
