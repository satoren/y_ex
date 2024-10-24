defmodule DocServerTestModule do
  use Yex.DocServer
  require Logger
  alias Yex.Doc

  def init(_arg, %{doc: doc} = state) do
    Doc.get_array(doc, "array")
    |> Yex.Array.insert(0, "server data")

    {:ok, state}
  end

  def handle_call(:get_doc, _from, %{doc: doc} = state) do
    {:reply, doc, state}
  end

  def handle_update_v1(doc, update, origin, state) do
    test_process = Process.whereis(:test_process)

    if test_process != nil and Process.alive?(test_process) do
      send(:test_process, {:doc_update, doc, update, origin})
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
    {:ok, pid} = DocServerTestModule.start_link([])

    doc = Doc.new()

    Doc.get_array(doc, "array")
    |> Array.insert(0, "local")

    Process.register(self(), :test_process)

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
      end
    end)

    assert_receive {:doc_update, _remote_doc, _update, "test"}
  end
end
