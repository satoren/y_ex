defmodule DocServerTestModule do
  use Yex.DocServer
  require Logger
  alias Yex.Awareness
  alias Yex.Doc

  def init(_arg, %{doc: doc, awareness: awareness} = state) do
    Doc.get_array(doc, "array")
    |> Yex.Array.insert(0, "server data")

    Awareness.set_local_state(awareness, %{"name" => "remote test user"})

    {:ok, assign(state, :assigned_at_init, "value")}
  end

  def handle_call(:get_doc, _from, %{doc: doc} = state) do
    {:reply, doc, state}
  end

  def handle_call(:get_assigns, _from, %{doc: _doc, assigns: assigns} = state) do
    {:reply, assigns, state}
  end

  def handle_update_v1(doc, update, origin, state) do
    test_process = state.assigns[:test_process]

    if test_process != nil do
      send(test_process, {:doc_update, doc, update, origin})
    end

    {:noreply, state}
  end

  def handle_awareness_change(awareness, change, origin, state) do
    test_process = state.assigns[:test_process]

    if test_process != nil do
      send(test_process, {:awareness_change, awareness, change, origin})
    end

    {:noreply, state}
  end
end

defmodule Yex.DocServerTest do
  use ExUnit.Case
  alias Yex.{Array, Doc, Sync}

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

  test "assigns" do
    {:ok, pid} = DocServerTestModule.start_link(assigns: %{initial_assigns_key: "value"})

    assert GenServer.call(pid, :get_assigns) == %{
             assigned_at_init: "value",
             initial_assigns_key: "value"
           }
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
  end
end
