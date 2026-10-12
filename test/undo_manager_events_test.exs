defmodule Yex.UndoManagerEventsTest.Worker do
  @moduledoc false
  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(_), do: {:ok, Yex.Doc.new(self())}

  @impl true
  def handle_call(:doc, _from, doc), do: {:reply, doc, doc}
  def handle_call({Yex.Doc, :run, fun}, _from, doc), do: {:reply, fun.(), doc}
end

defmodule Yex.UndoManagerEventsTest do
  use ExUnit.Case, async: true

  alias Yex.{Array, Doc, Map, Text, UndoManager, XmlElementPrelim, XmlFragment}
  alias Yex.UndoManager.{Options, StackClearedEvent, StackItemEvent}
  alias Yex.UndoManagerEventsTest.Worker

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    {:ok, undo_manager} = UndoManager.new(doc, text)
    {:ok, doc: doc, text: text, undo_manager: undo_manager}
  end

  defp new_text_manager(doc, text, timeout \\ 500) do
    {:ok, undo_manager} =
      UndoManager.new_with_options(doc, text, %Options{capture_timeout: timeout})

    undo_manager
  end

  # A document served by another process, so spawned processes can use it too.
  defp worker_text_manager do
    {:ok, worker} = Worker.start_link()
    doc = GenServer.call(worker, :doc)
    text = Doc.get_text(doc, "text")
    {:ok, um} = UndoManager.new(doc, text)
    {text, um}
  end

  defmacrop assert_event(ref, pattern) do
    quote do
      assert_receive {:undo_manager_event, ^unquote(ref), unquote(pattern), _metadata}
    end
  end

  defp added_id(ref) do
    assert_receive {:undo_manager_event, ^ref, %StackItemEvent{type: :added, item: id}, _}
    id
  end

  describe "stack events" do
    test "a captured change emits :added", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")

      assert_event(ref, %StackItemEvent{
        type: :added,
        kind: :undo,
        item: id,
        origin: nil,
        meta: nil
      })

      assert is_integer(id) and id > 0
    end

    test "a change merged into the last item emits :updated with the same id", %{
      text: text,
      undo_manager: um
    } do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      Text.insert(text, 1, "b")
      assert_event(ref, %StackItemEvent{type: :updated, kind: :undo, item: ^id})
    end

    test "stop_capturing starts a new item", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id1 = added_id(ref)
      UndoManager.stop_capturing(um)
      Text.insert(text, 1, "b")
      id2 = added_id(ref)
      assert id1 != id2
    end

    test "capture_timeout 0 emits :added for every change", %{doc: doc, text: text} do
      um = new_text_manager(doc, text, 0)
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      Text.insert(text, 1, "b")
      id1 = added_id(ref)
      id2 = added_id(ref)
      assert id1 != id2
      refute_received {:undo_manager_event, ^ref, %StackItemEvent{type: :updated}, _}
    end

    test "undo emits :added on the redo stack, then :popped", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)

      UndoManager.undo(um)

      assert_receive {:undo_manager_event, ^ref, first, _}
      assert_receive {:undo_manager_event, ^ref, second, _}

      assert %StackItemEvent{type: :added, kind: :redo, item: redo_id, origin: ^um, meta: nil} =
               first

      assert %StackItemEvent{type: :popped, kind: :undo, item: ^id, origin: ^um} = second
      assert redo_id != id
    end

    test "redo emits :added on the undo stack, then :popped", %{text: text, undo_manager: um} do
      Text.insert(text, 0, "a")
      UndoManager.undo(um)
      ref = UndoManager.observe(um)

      UndoManager.redo(um)
      assert_receive {:undo_manager_event, ^ref, first, _}
      assert_receive {:undo_manager_event, ^ref, second, _}
      assert %StackItemEvent{type: :added, kind: :undo, origin: ^um} = first
      assert %StackItemEvent{type: :popped, kind: :redo, origin: ^um} = second
    end

    test "undo on an empty stack emits nothing", %{undo_manager: um} do
      ref = UndoManager.observe(um)
      UndoManager.undo(um)
      UndoManager.redo(um)
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "tracked origins are reported; untracked changes emit nothing", %{
      doc: doc,
      text: text,
      undo_manager: um
    } do
      UndoManager.include_origin(um, "mine")
      ref = UndoManager.observe(um)

      Doc.transaction(doc, "mine", fn -> Text.insert(text, 0, "a") end)
      assert_event(ref, %StackItemEvent{type: :added, origin: "mine"})

      Doc.transaction(doc, "other", fn -> Text.insert(text, 0, "b") end)
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "changes outside the scope emit nothing", %{doc: doc, undo_manager: um} do
      ref = UndoManager.observe(um)
      Array.push(Doc.get_array(doc, "other"), 1)
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "remote updates applied with an untracked origin emit nothing", %{
      doc: doc,
      undo_manager: um
    } do
      ref = UndoManager.observe(um)
      remote = Doc.new()
      Text.insert(Doc.get_text(remote, "text"), 0, "remote")
      {:ok, update} = Yex.encode_state_as_update(remote)
      Doc.transaction(doc, "remote", fn -> Yex.apply_update(doc, update) end)
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "clear emits StackClearedEvent", %{doc: doc, text: text} do
      um = new_text_manager(doc, text, 0)
      ref = UndoManager.observe(um)

      UndoManager.clear(um)
      refute_receive {:undo_manager_event, ^ref, %StackClearedEvent{}, _}, 10

      Text.insert(text, 0, "a")
      UndoManager.clear(um)

      assert_event(ref, %StackClearedEvent{undo_stack_cleared: true, redo_stack_cleared: false})

      Text.insert(text, 0, "a")
      Text.insert(text, 0, "b")
      UndoManager.undo(um)
      UndoManager.clear(um)
      assert_event(ref, %StackClearedEvent{undo_stack_cleared: true, redo_stack_cleared: true})
    end

    test "several changes in one transaction emit one event at commit", %{
      doc: doc,
      text: text,
      undo_manager: um
    } do
      ref = UndoManager.observe(um)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "a")
        Text.insert(text, 1, "b")
        refute_received {:undo_manager_event, ^ref, _, _}
      end)

      assert_event(ref, %StackItemEvent{type: :added})
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "observe works inside a transaction and sees its capture", %{
      doc: doc,
      text: text,
      undo_manager: um
    } do
      ref =
        Doc.transaction(doc, fn ->
          Text.insert(text, 0, "a")
          UndoManager.observe(um)
        end)

      assert_event(ref, %StackItemEvent{type: :added})
    end

    test "metadata is delivered as the fourth element", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um, metadata: :meta)
      default_ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      assert_receive {:undo_manager_event, ^ref, %StackItemEvent{}, :meta}
      assert_receive {:undo_manager_event, ^default_ref, %StackItemEvent{}, nil}
    end

    test "unobserve stops events and is idempotent", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      assert :ok = UndoManager.unobserve(ref)
      assert :ok = UndoManager.unobserve(ref)
      Text.insert(text, 0, "a")
      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "unobserve inside a transaction", %{doc: doc, text: text, undo_manager: um} do
      ref = UndoManager.observe(um)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "a")
        assert :ok = UndoManager.unobserve(ref)
      end)

      refute_receive {:undo_manager_event, ^ref, _, _}, 10
    end

    test "each subscriber gets every event", %{text: text, undo_manager: um} do
      ref1 = UndoManager.observe(um)
      ref2 = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      assert_event(ref1, %StackItemEvent{type: :added})
      assert_event(ref2, %StackItemEvent{type: :added})

      UndoManager.unobserve(ref1)
      UndoManager.stop_capturing(um)
      Text.insert(text, 0, "b")
      assert_event(ref2, %StackItemEvent{type: :added})
      refute_receive {:undo_manager_event, ^ref1, _, _}, 10
    end

    test "events are in the mailbox when the change returns", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      assert_received {:undo_manager_event, ^ref, %StackItemEvent{type: :added}, _}
    end

    test "every scope type emits :added", %{doc: doc} do
      cases = [
        {Doc.get_array(doc, "a"), &Array.push(&1, 1)},
        {Doc.get_map(doc, "m"), &Map.set(&1, "k", 1)},
        {Doc.get_xml_fragment(doc, "x"), &XmlFragment.push(&1, XmlElementPrelim.empty("div"))}
      ]

      for {scope, change} <- cases do
        {:ok, um} = UndoManager.new(doc, scope)
        ref = UndoManager.observe(um)
        change.(scope)
        assert_event(ref, %StackItemEvent{type: :added, kind: :undo})
      end
    end

    test "two managers on one doc report only their own items", %{doc: doc, text: text} do
      um1 = new_text_manager(doc, text)
      array = Doc.get_array(doc, "array")
      {:ok, um2} = UndoManager.new(doc, array)
      ref1 = UndoManager.observe(um1)
      ref2 = UndoManager.observe(um2)

      Text.insert(text, 0, "a")
      id1 = added_id(ref1)
      refute_receive {:undo_manager_event, ^ref2, _, _}, 10

      Array.push(array, 1)
      id2 = added_id(ref2)
      refute_receive {:undo_manager_event, ^ref1, _, _}, 10
      assert id1 != id2
    end
  end

  describe "subscription lifetime" do
    test "a subscriber in another process receives events" do
      {text, um} = worker_text_manager()

      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      assert_received {:undo_manager_event, ^ref, %StackItemEvent{type: :added}, _}
    end

    test "a dead subscriber leaves the manager working" do
      {text, um} = worker_text_manager()
      parent = self()

      pid =
        spawn(fn ->
          UndoManager.observe(um)
          send(parent, :subscribed)
        end)

      assert_receive :subscribed
      Process.monitor(pid)
      assert_receive {:DOWN, _, :process, ^pid, _}
      :erlang.garbage_collect()

      Text.insert(text, 0, "a")
      assert :ok = UndoManager.undo(um)
      assert Text.to_string(text) == ""

      ref = UndoManager.observe(um)
      UndoManager.redo(um)
      assert_event(ref, %StackItemEvent{type: :popped, kind: :redo})
    end

    test "a dead subscriber needs no manager call before edits continue" do
      {text, um} = worker_text_manager()
      pid = spawn(fn -> UndoManager.observe(um) end)
      Process.monitor(pid)
      assert_receive {:DOWN, _, :process, ^pid, _}
      :erlang.garbage_collect()

      Text.insert(text, 0, "a")
      Text.insert(text, 1, "b")
      assert Text.to_string(text) == "ab"
    end

    test "the subscription keeps a dropped manager capturing", %{doc: doc, text: text} do
      ref = UndoManager.observe(new_text_manager(doc, text))
      :erlang.garbage_collect()

      Text.insert(text, 0, "a")
      assert_event(ref, %StackItemEvent{type: :added})

      UndoManager.unobserve(ref)
      :erlang.garbage_collect()
      Text.insert(text, 1, "b")
      Text.insert(text, 2, "c")
      assert Text.to_string(text) == "abc"
    end
  end

  describe "meta" do
    test "meta set on :added comes back on :popped", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      assert :ok = UndoManager.put_meta(um, id, %{cursor: 1})

      UndoManager.undo(um)
      assert_event(ref, %StackItemEvent{type: :popped, item: ^id, meta: %{cursor: 1}})
    end

    test "get_meta defaults to nil and round trips", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      assert {:ok, nil} = UndoManager.get_meta(um, id)
      UndoManager.put_meta(um, id, {:cursor, 3})
      assert {:ok, {:cursor, 3}} = UndoManager.get_meta(um, id)
    end

    test "meta survives a merge and is reported on :updated", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      UndoManager.put_meta(um, id, :first)

      Text.insert(text, 1, "b")
      assert_event(ref, %StackItemEvent{type: :updated, item: ^id, meta: :first})

      UndoManager.undo(um)
      assert_event(ref, %StackItemEvent{type: :popped, item: ^id, meta: :first})
      assert Text.to_string(text) == ""
    end

    test "meta on the redo item comes back when redoing", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      _ = added_id(ref)
      UndoManager.undo(um)

      assert_event(ref, %StackItemEvent{type: :added, kind: :redo, item: redo_id})
      UndoManager.put_meta(um, redo_id, :redo_meta)

      UndoManager.redo(um)

      assert_event(ref, %StackItemEvent{
        type: :popped,
        kind: :redo,
        item: ^redo_id,
        meta: :redo_meta
      })
    end

    test "popped, cleared and unknown items are not found", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      assert {:error, :not_found} = UndoManager.get_meta(um, 0)
      assert {:error, :not_found} = UndoManager.put_meta(um, 123_456_789_012, :x)

      Text.insert(text, 0, "a")
      id = added_id(ref)
      UndoManager.undo(um)
      assert {:error, :not_found} = UndoManager.get_meta(um, id)
      assert {:error, :not_found} = UndoManager.put_meta(um, id, :x)

      assert_event(ref, %StackItemEvent{type: :added, kind: :redo, item: redo_id})
      UndoManager.clear(um)
      assert {:error, :not_found} = UndoManager.get_meta(um, redo_id)
    end

    test "a new edit drops redo items and their meta", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      UndoManager.undo(um)
      assert_event(ref, %StackItemEvent{type: :added, kind: :redo, item: redo_id})
      UndoManager.put_meta(um, redo_id, :x)

      Text.insert(text, 0, "b")
      assert {:error, :not_found} = UndoManager.get_meta(um, redo_id)
    end

    test "an item popped without changes emits no :popped and is gone", %{
      doc: doc,
      text: text,
      undo_manager: um
    } do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      Doc.transaction(doc, "untracked", fn -> Text.delete(text, 0, 1) end)

      assert {:ok, false} = UndoManager.undo_with_result(um)
      refute_receive {:undo_manager_event, ^ref, %StackItemEvent{type: :popped}, _}, 10
      assert {:error, :not_found} = UndoManager.get_meta(um, id)
    end

    test "a sticky index stored as meta resolves after undo", %{text: text, undo_manager: um} do
      Text.insert(text, 0, "hello")
      UndoManager.stop_capturing(um)
      ref = UndoManager.observe(um)

      cursor = Yex.StickyIndex.new(text, 2, :after)
      Text.insert(text, 5, " world")
      UndoManager.put_meta(um, added_id(ref), cursor)

      UndoManager.undo(um)
      assert_event(ref, %StackItemEvent{type: :popped, meta: popped})
      assert {:ok, %{index: 2}} = Yex.StickyIndex.get_offset(popped)
    end

    test "meta functions work inside a transaction", %{doc: doc, text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)

      Doc.transaction(doc, fn ->
        assert :ok = UndoManager.put_meta(um, id, :in_txn)
        assert {:ok, :in_txn} = UndoManager.get_meta(um, id)
      end)
    end

    test "arbitrary terms round trip", %{text: text, undo_manager: um} do
      ref = UndoManager.observe(um)
      Text.insert(text, 0, "a")
      id = added_id(ref)
      term = %{bin: <<1, 2, 3>>, pid: self(), ref: make_ref(), list: [1, {2, "three"}]}
      UndoManager.put_meta(um, id, term)
      assert {:ok, ^term} = UndoManager.get_meta(um, id)
    end

    test "an undo from another process before put_meta loses the meta" do
      {text, um} = worker_text_manager()
      test_pid = self()

      subscriber =
        spawn(fn ->
          ref = UndoManager.observe(um)
          send(test_pid, :subscribed)

          receive do
            :continue -> :ok
          end

          assert_receive {:undo_manager_event, ^ref, %StackItemEvent{type: :added, item: id}, _}
          send(test_pid, {:put_meta, UndoManager.put_meta(um, id, :late)})

          assert_receive {:undo_manager_event, ^ref, %StackItemEvent{type: :popped, meta: meta},
                          _}

          send(test_pid, {:popped_meta, meta})
        end)

      assert_receive :subscribed
      Text.insert(text, 0, "a")
      UndoManager.undo(um)
      send(subscriber, :continue)

      assert_receive {:put_meta, {:error, :not_found}}
      assert_receive {:popped_meta, nil}
    end
  end

  describe "manager lifetime" do
    test "a dropped manager whose meta holds the document leaves the document usable" do
      {text, cursor} = dropped_manager_with_cursor_meta()
      :erlang.garbage_collect()

      Text.insert(text, 1, "b")
      assert Text.to_string(text) == "ab"
      assert {:ok, %{index: 0}} = Yex.StickyIndex.get_offset(cursor)
    end
  end

  # Leaves no reference to the manager or its subscription behind.
  defp dropped_manager_with_cursor_meta do
    {text, um} = worker_text_manager()
    ref = UndoManager.observe(um)
    Text.insert(text, 0, "a")
    cursor = Yex.StickyIndex.new(text, 0, :after)
    :ok = UndoManager.put_meta(um, added_id(ref), cursor)
    UndoManager.unobserve(ref)
    {text, cursor}
  end

  describe "stack sizes" do
    test "empty manager", %{undo_manager: um} do
      assert UndoManager.undo_stack_size(um) == 0
      assert UndoManager.redo_stack_size(um) == 0
    end

    test "track captures, merges, undo and clear", %{text: text, undo_manager: um} do
      Text.insert(text, 0, "a")
      Text.insert(text, 1, "b")
      assert UndoManager.undo_stack_size(um) == 1

      UndoManager.stop_capturing(um)
      Text.insert(text, 2, "c")
      assert UndoManager.undo_stack_size(um) == 2

      UndoManager.undo(um)
      assert UndoManager.undo_stack_size(um) == 1
      assert UndoManager.redo_stack_size(um) == 1

      UndoManager.clear(um)
      assert UndoManager.undo_stack_size(um) == 0
      assert UndoManager.redo_stack_size(um) == 0
    end

    test "an open transaction is not counted until commit", %{
      doc: doc,
      text: text,
      undo_manager: um
    } do
      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "a")
        assert UndoManager.undo_stack_size(um) == 0
      end)

      assert UndoManager.undo_stack_size(um) == 1
    end
  end
end
