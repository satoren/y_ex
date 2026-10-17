defmodule Yex.DocLifecycleTest do
  use ExUnit.Case, async: true

  alias Yex.{Array, Doc, Map, Subscription, Text, UndoManager}

  defmodule Worker do
    use GenServer

    def init(state), do: {:ok, state}
    def handle_call({Yex.Doc, :run, fun}, _from, state), do: {:reply, fun.(), state}
  end

  defp doc(client_id), do: Doc.with_options(%Doc.Options{client_id: client_id})

  # A parent with a map "folder" holding one subdoc under "a".
  defp parent_with_subdoc do
    parent = doc(1)
    folder = Doc.get_map(parent, "folder")
    sub = Doc.with_options(%Doc.Options{guid: "sub"})
    :ok = Map.set(folder, "a", sub)
    {parent, folder, Map.fetch!(folder, "a")}
  end

  describe "monitor_transaction_cleanup/2" do
    test "reports states and an empty delete set for an insert" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, ref} = Doc.monitor_transaction_cleanup(doc)

      Text.insert(text, 0, "Hello")

      assert_receive {:transaction_cleanup, %Yex.TransactionCleanupEvent{} = event, nil, ^doc}
      assert event.before_state == %{}
      assert event.after_state == %{7 => 5}
      assert event.delete_set == %{}
      :ok = Subscription.unsubscribe(ref)
    end

    test "reports deleted ranges as {clock, len}, ascending and squashed" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "abcdefgh")
      {:ok, _} = Doc.monitor_transaction_cleanup(doc, metadata: :meta)

      Text.delete(text, 1, 2)
      assert_receive {:transaction_cleanup, event, nil, :meta}
      assert event.delete_set == %{7 => [{1, 2}]}
      assert event.before_state == event.after_state

      # "adefgh": two non-adjacent ranges, then two adjacent deletes in one transaction.
      Doc.transaction(doc, fn ->
        Text.delete(text, 4, 1)
        Text.delete(text, 0, 1)
      end)

      assert_receive {:transaction_cleanup, event, nil, :meta}
      assert event.delete_set == %{7 => [{0, 1}, {6, 1}]}

      Doc.transaction(doc, fn ->
        Text.delete(text, 0, 1)
        Text.delete(text, 0, 1)
      end)

      assert_receive {:transaction_cleanup, event, nil, :meta}
      assert event.delete_set == %{7 => [{3, 2}]}
    end

    test "carries the transaction origin and the undo manager origin" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, undo} = UndoManager.new(doc, text)
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)

      Doc.transaction(doc, "origin", fn -> Text.insert(text, 0, "Hi") end)
      assert_receive {:transaction_cleanup, _, "origin", _}

      Text.insert(text, 0, "Hello")
      assert_receive {:transaction_cleanup, _, nil, _}
      :ok = UndoManager.undo(undo)
      assert_receive {:transaction_cleanup, event, %UndoManager{}, _}
      assert event.delete_set != %{}
    end

    test "reports remote v1 and v2 updates with the remote client in after_state" do
      source = doc(3)
      Text.insert(Doc.get_text(source, "text"), 0, "abc")
      {:ok, v1} = Yex.encode_state_as_update_v1(source)
      {:ok, v2} = Yex.encode_state_as_update_v2(source)

      for {apply, update} <- [{&Yex.apply_update_v1/2, v1}, {&Yex.apply_update_v2/2, v2}] do
        doc = doc(9)
        {:ok, _} = Doc.monitor_transaction_cleanup(doc)
        :ok = apply.(doc, update)
        assert_receive {:transaction_cleanup, event, nil, ^doc}
        assert event.before_state == %{}
        assert event.after_state == %{3 => 3}
      end
    end

    test "skips transactions that changed nothing" do
      doc = doc(7)
      Text.insert(Doc.get_text(doc, "text"), 0, "content")
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)

      _ = Doc.get_text(doc, "text")
      {:ok, ref} = Doc.monitor_update(doc)
      :ok = Doc.demonitor_update(ref)
      Doc.transaction(doc, fn -> :ok end)

      refute_receive {:transaction_cleanup, _, _, _}, 10
    end

    test "registered inside a transaction, reports that transaction" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")

      Doc.transaction(doc, fn ->
        {:ok, _} = Doc.monitor_transaction_cleanup(doc)
        Text.insert(text, 0, "Hi")
      end)

      assert_receive {:transaction_cleanup, %{after_state: %{7 => 2}}, nil, _}
    end

    test "does not report a remote update held as pending until it integrates" do
      source = doc(1)
      text = Doc.get_text(source, "text")
      Text.insert(text, 0, "a")
      first = Yex.encode_state_as_update!(source)
      sv = Yex.encode_state_vector!(source)
      Text.insert(text, 1, "b")
      second = Yex.encode_state_as_update!(source, sv)

      target = doc(2)
      {:ok, _} = Doc.monitor_transaction_cleanup(target)
      :ok = Yex.apply_update(target, second)
      assert {:ok, pending} = Doc.get_pending_update(target)
      assert is_binary(pending)
      refute_receive {:transaction_cleanup, _, _, _}, 10

      :ok = Yex.apply_update(target, first)
      assert_receive {:transaction_cleanup, %{before_state: %{}, after_state: %{1 => 2}}, nil, _}
    end

    test "arrives before the update message of the same commit" do
      doc = doc(7)
      {:ok, _} = Doc.monitor_update(doc)
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)
      Text.insert(Doc.get_text(doc, "text"), 0, "Hi")

      assert_receive message1
      assert_receive message2
      assert {:transaction_cleanup, _, _, _} = message1
      assert {:update_v1, _, _, _} = message2
    end

    test "is reported when the transaction function raises" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)
      {:ok, _} = Doc.monitor_update(doc)

      assert_raise RuntimeError, fn ->
        Doc.transaction(doc, fn ->
          Text.insert(text, 0, "Hi")
          raise "boom"
        end)
      end

      assert_receive {:transaction_cleanup, %{after_state: %{7 => 2}}, nil, _}
      assert_receive {:update_v1, _, nil, _}
      assert :ok = Text.insert(text, 2, "!")
    end

    test "stops after unsubscribe, inside and outside a transaction" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, ref1} = Doc.monitor_transaction_cleanup(doc)
      {:ok, ref2} = Doc.monitor_transaction_cleanup(doc)

      :ok = Subscription.unsubscribe(ref1)

      Doc.transaction(doc, fn ->
        :ok = Subscription.unsubscribe(ref2)
        Text.insert(text, 0, "Hi")
      end)

      refute_receive {:transaction_cleanup, _, _, _}, 10
    end

    test "works through a worker process" do
      {:ok, worker} = GenServer.start_link(Worker, nil)
      doc = Doc.new(worker)
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)
      Text.insert(Doc.get_text(doc, "text"), 0, "Hi")
      assert_receive {:transaction_cleanup, %{delete_set: %{}}, nil, ^doc}
    end
  end

  describe "destroy/1 and monitor_destroy/2" do
    test "notifies and drops document-level subscriptions of a root doc" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, _} = Doc.monitor_destroy(doc)
      {:ok, _} = Doc.monitor_destroy(doc, metadata: :meta)
      {:ok, _} = Doc.monitor_update(doc)
      {:ok, _} = Doc.monitor_transaction_cleanup(doc)
      observe_ref = Yex.SharedType.observe(text)

      assert :ok = Doc.destroy(doc)
      assert_receive {:destroy, ^doc}
      assert_receive {:destroy, :meta}

      Text.insert(text, 0, "Hi")
      assert Text.to_string(text) == "Hi"
      assert_receive {:observe_event, ^observe_ref, _, _, _}
      refute_receive {:update_v1, _, _, _}, 10
      refute_received {:transaction_cleanup, _, _, _}

      {:ok, _} = Doc.monitor_update(doc)
      Text.insert(text, 0, "!")
      assert_receive {:update_v1, _, nil, ^doc}

      assert :ok = Doc.destroy(doc)
      refute_receive {:destroy, _}, 10
    end

    test "registered inside a transaction, fires on a later destroy" do
      doc = doc(7)
      Doc.transaction(doc, fn -> {:ok, _} = Doc.monitor_destroy(doc) end)
      :ok = Doc.destroy(doc)
      assert_receive {:destroy, ^doc}
    end

    test "an undo manager on a destroyed doc does not raise" do
      doc = doc(7)
      text = Doc.get_text(doc, "text")
      {:ok, undo} = UndoManager.new(doc, text)
      Text.insert(text, 0, "Hi")
      :ok = Doc.destroy(doc)
      assert :ok = UndoManager.undo(undo)
    end

    test "unsubscribing after destroy is fine" do
      doc = doc(7)
      {:ok, ref} = Doc.monitor_destroy(doc)
      :ok = Doc.destroy(doc)
      assert :ok = Subscription.unsubscribe(ref)
    end

    test "replaces a subdoc in its parent with an unloaded copy" do
      {parent, folder, sub} = parent_with_subdoc()
      Text.insert(Doc.get_text(sub, "text"), 0, "content")
      {:ok, _} = Doc.monitor_subdocs(parent)
      {:ok, _} = Doc.monitor_transaction_cleanup(parent)
      {:ok, _} = Doc.monitor_destroy(sub)

      :ok = Doc.destroy(sub)

      assert_receive {:destroy, ^sub}
      assert_receive {:subdocs, %{added: [added], removed: [removed], loaded: []}, nil, ^parent}
      assert Doc.guid(added) == "sub"
      assert Doc.guid(removed) == "sub"
      # Swapping the copy into the parent's item changes no content of the parent.
      refute_receive {:transaction_cleanup, _, _, _}, 10

      live = Map.fetch!(folder, "a")
      assert Doc.guid(live) == "sub"
      assert live.reference != sub.reference
      assert Doc.should_load(live) == false
      assert Text.to_string(Doc.get_text(live, "text")) == ""

      :ok = Doc.load(live)
      assert_receive {:subdocs, %{added: [], removed: [], loaded: [loaded]}, nil, ^parent}
      assert loaded.reference == live.reference
    end

    # yrs 0.28 Doc::destroy reports the replacement copy as removed (yjs reports the
    # destroyed doc) and then destroys the copy at commit, leaving a second copy in the
    # item. These assertions pin that; they flip when yrs is fixed.
    test "pins yrs 0.28 bookkeeping after destroying a subdoc" do
      {parent, folder, sub} = parent_with_subdoc()
      {:ok, _} = Doc.monitor_subdocs(parent)

      :ok = Doc.destroy(sub)
      assert_receive {:subdocs, %{added: [added]}, _, _}

      live = Map.fetch!(folder, "a")
      assert added.reference != live.reference
      # The doc handed out in `added` is destroyed already: loading it does nothing.
      :ok = Doc.load(added)
      refute_receive {:subdocs, _, _, _}, 10

      # The parent still lists the destroyed doc, not the live copy, and listing it
      # replaces the cached resource for the guid.
      assert [listed] = Doc.subdocs(parent)
      assert Doc.guid(listed) == "sub"
      assert listed.reference != live.reference
      assert Map.fetch!(folder, "a").reference != live.reference

      # Destroying the parent does not reach the live copy.
      live = Map.fetch!(folder, "a")
      {:ok, _} = Doc.monitor_destroy(live)
      :ok = Doc.destroy(parent)
      refute_received {:destroy, ^live}
    end

    test "destroying a doc removed from its parent sends nothing" do
      {parent, folder, sub} = parent_with_subdoc()
      {:ok, _} = Doc.monitor_destroy(sub)
      {:ok, _} = Doc.monitor_subdocs(parent)

      :ok = Map.delete(folder, "a")
      assert_receive {:destroy, ^sub}
      assert_receive {:subdocs, %{added: [], removed: [_]}, _, _}

      :ok = Doc.destroy(sub)
      refute_receive {:subdocs, %{added: [_]}, _, _}, 10
    end

    test "Map.delete of a subdoc inside the parent's transaction destroys it on commit" do
      {parent, folder, sub} = parent_with_subdoc()
      {:ok, _} = Doc.monitor_destroy(sub)

      Doc.transaction(parent, fn ->
        :ok = Map.delete(folder, "a")
        refute_received {:destroy, _}
      end)

      assert_receive {:destroy, ^sub}
    end

    test "destroying a root doc destroys its subdocs" do
      {parent, _folder, sub} = parent_with_subdoc()
      {:ok, _} = Doc.monitor_destroy(sub, metadata: :sub)
      {:ok, _} = Doc.monitor_destroy(parent, metadata: :parent)

      :ok = Doc.destroy(parent)
      assert_receive {:destroy, :sub}
      assert_receive {:destroy, :parent}
    end

    test "raises instead of blocking when a transaction is open" do
      {parent, _folder, sub} = parent_with_subdoc()

      Doc.transaction(sub, fn ->
        assert_raise Yex.TransactionAcqError, fn -> Doc.destroy(sub) end
        assert_raise Yex.TransactionAcqError, fn -> Doc.destroy(parent) end
      end)

      Doc.transaction(parent, fn ->
        assert_raise Yex.TransactionAcqError, fn -> Doc.destroy(sub) end
        assert_raise Yex.TransactionAcqError, fn -> Doc.destroy(parent) end
      end)

      assert :ok = Doc.destroy(sub)
    end

    test "works through a worker process" do
      {:ok, worker} = GenServer.start_link(Worker, nil)
      doc = Doc.new(worker)
      {:ok, _} = Doc.monitor_destroy(doc)
      assert :ok = Doc.destroy(doc)
      assert_receive {:destroy, ^doc}
    end
  end

  describe "load/1" do
    defp remote_subdoc(options) do
      source = doc(1)
      :ok = Map.set(Doc.get_map(source, "folder"), "a", Doc.with_options(options))
      {:ok, update} = Yex.encode_state_as_update(source)

      remote = doc(2)
      {:ok, _} = Doc.monitor_subdocs(remote)
      :ok = Yex.apply_update(remote, update)
      assert_receive {:subdocs, %{added: [sub]}, _, ^remote}
      {remote, sub}
    end

    test "loads a subdoc received from a remote peer once" do
      {remote, sub} = remote_subdoc(%Doc.Options{guid: "sub"})
      refute_received {:subdocs, _, _, _}
      assert Doc.should_load(sub) == false

      assert :ok = Doc.load(sub)
      assert_receive {:subdocs, %{added: [], removed: [], loaded: [loaded]}, nil, ^remote}
      assert loaded.reference == sub.reference
      assert Doc.should_load(sub) == true

      assert :ok = Doc.load(sub)
      refute_receive {:subdocs, _, _, _}, 10
    end

    test "an auto_load subdoc arrives loaded" do
      {_remote, sub} = remote_subdoc(%Doc.Options{guid: "sub", auto_load: true})
      assert Doc.should_load(sub) == true
      :ok = Doc.load(sub)
      refute_receive {:subdocs, %{loaded: [_]}, _, _}, 10
    end

    test "on a root doc only sets should_load" do
      doc = Doc.with_options(%Doc.Options{should_load: false})
      assert :ok = Doc.load(doc)
      assert Doc.should_load(doc) == true
    end

    test "raises instead of blocking when a transaction is open" do
      {remote, sub} = remote_subdoc(%Doc.Options{guid: "sub"})

      Doc.transaction(remote, fn ->
        assert_raise Yex.TransactionAcqError, fn -> Doc.load(sub) end
      end)

      Doc.transaction(sub, fn ->
        assert_raise Yex.TransactionAcqError, fn -> Doc.load(sub) end
      end)

      assert Doc.should_load(sub) == false
      assert :ok = Doc.load(sub)
    end
  end

  describe "force_gc/1" do
    defp skip_gc_doc_with_deleted_text do
      doc = Doc.with_options(%Doc.Options{client_id: 1, skip_gc: true})
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, String.duplicate("x", 200))
      Text.delete(text, 0, 200)
      Text.insert(text, 0, "kept")
      {doc, text}
    end

    test "collects deleted content of a skip_gc doc, v1 and v2" do
      {doc, text} = skip_gc_doc_with_deleted_text()
      {:ok, v1_before} = Yex.encode_state_as_update_v1(doc)
      {:ok, v2_before} = Yex.encode_state_as_update_v2(doc)

      assert :ok = Doc.force_gc(doc)

      {:ok, v1_after} = Yex.encode_state_as_update_v1(doc)
      {:ok, v2_after} = Yex.encode_state_as_update_v2(doc)
      assert byte_size(v1_after) < byte_size(v1_before)
      assert byte_size(v2_after) < byte_size(v2_before)
      assert Text.to_string(text) == "kept"

      for {apply, update} <- [
            {&Yex.apply_update_v1/2, v1_after},
            {&Yex.apply_update_v2/2, v2_after}
          ] do
        copy = Doc.new()
        :ok = apply.(copy, update)
        assert Text.to_string(Doc.get_text(copy, "text")) == "kept"
      end
    end

    test "keeps content on an undo stack" do
      doc = Doc.with_options(%Doc.Options{skip_gc: true})
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "Hello")
      {:ok, undo} = UndoManager.new(doc, text)
      Text.delete(text, 0, 5)

      :ok = Doc.force_gc(doc)
      :ok = UndoManager.undo(undo)
      assert Text.to_string(text) == "Hello"
    end

    test "leaves a default doc and overwritten map keys intact" do
      doc = Doc.new()
      map = Doc.get_map(doc, "map")
      array = Doc.get_array(doc, "array")
      Map.set(map, "k", 1)
      Map.set(map, "k", 2)
      Array.push(array, 1)
      Array.delete(array, 0)

      assert :ok = Doc.force_gc(doc)
      assert Map.to_map(map) == %{"k" => 2}
      assert Array.to_list(array) == []
    end

    test "works through a worker process" do
      {:ok, worker} = GenServer.start_link(Worker, nil)
      doc = Doc.new(worker)
      assert :ok = Doc.force_gc(doc)
    end
  end

  describe "subdocs/1" do
    test "lists the subdocs with the references the container hands out" do
      parent = doc(1)
      assert Doc.subdocs(parent) == []

      folder = Doc.get_map(parent, "folder")
      :ok = Map.set(folder, "a", Doc.with_options(%Doc.Options{guid: "a"}))
      :ok = Map.set(folder, "b", Doc.with_options(%Doc.Options{guid: "b"}))

      listed = Doc.subdocs(parent)
      assert listed |> Enum.map(&Doc.guid/1) |> Enum.sort() == ["a", "b"]

      for doc <- listed do
        assert doc.reference == Map.fetch!(folder, Doc.guid(doc)).reference
      end

      :ok = Map.delete(folder, "a")
      assert Enum.map(Doc.subdocs(parent), &Doc.guid/1) == ["b"]
    end

    test "lists a subdoc inserted in an open transaction after commit" do
      parent = doc(1)
      folder = Doc.get_map(parent, "folder")

      Doc.transaction(parent, fn ->
        :ok = Map.set(folder, "a", Doc.new())
        assert Doc.subdocs(parent) == []
      end)

      assert [_] = Doc.subdocs(parent)
    end

    test "listing a destroyed subdoc evicts the cached replacement" do
      {parent, folder, sub} = parent_with_subdoc()
      :ok = Doc.destroy(sub)
      live = Map.fetch!(folder, "a")
      assert Map.fetch!(folder, "a").reference == live.reference

      assert [listed] = Doc.subdocs(parent)
      assert Doc.guid(listed) == "sub"
      assert Map.fetch!(folder, "a").reference != live.reference
    end

    test "works through a worker process" do
      {:ok, worker} = GenServer.start_link(Worker, nil)
      parent = Doc.new(worker)
      :ok = Map.set(Doc.get_map(parent, "folder"), "a", Doc.with_options(%Doc.Options{guid: "a"}))
      assert [sub] = Doc.subdocs(parent)
      assert Doc.guid(sub) == "a"
    end
  end
end
