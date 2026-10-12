defmodule Yex.SubdocsTest do
  use ExUnit.Case, async: true

  alias Yex.{
    Doc,
    Text,
    Map
  }

  test "new" do
    root_doc = Doc.new()
    folder = Doc.get_map(root_doc, "text")
    {:ok, monitor_ref} = Doc.monitor_subdocs(root_doc)

    sub_doc = Doc.new()
    sub_doc_text = Doc.get_text(sub_doc, "subdoc-text")
    Text.insert(sub_doc_text, 0, "some initial content")
    Map.set(folder, "my-document.txt", sub_doc)

    assert_receive {:subdocs, %{added: added, loaded: loaded, removed: []}, _, ^root_doc}

    assert length(added) == 1
    assert length(loaded) == 1
    assert Doc.guid(sub_doc) == Doc.guid(hd(added))
    assert Doc.guid(sub_doc) == Doc.guid(hd(loaded))

    [added_doc] = added
    [loaded_doc] = loaded

    # Regression: the same logical subdoc must reuse the same NIF resource ref.
    assert added_doc.reference == loaded_doc.reference

    from_map_1 = Map.get(folder, "my-document.txt")
    from_map_2 = Map.get(folder, "my-document.txt")

    assert %Doc{} = from_map_1
    assert %Doc{} = from_map_2
    assert Doc.guid(from_map_1) == Doc.guid(added_doc)
    assert from_map_1.reference == added_doc.reference
    assert from_map_1.reference == from_map_2.reference

    :ok = Doc.demonitor_update(monitor_ref)
  end

  test "subdoc cache prunes removed entries across distinct add/remove/re-add" do
    root_doc = Doc.new()
    folder = Doc.get_map(root_doc, "text")
    {:ok, monitor_ref} = Doc.monitor_subdocs(root_doc)

    sub_doc_a = Doc.new()
    sub_doc_b = Doc.new()

    :ok = Map.set(folder, "a", sub_doc_a)

    assert_receive {:subdocs, %{added: [added_a], removed: [], loaded: [_loaded_a]}, _, ^root_doc}

    first_a_ref = added_a.reference

    :ok = Map.delete(folder, "a")

    assert_receive {:subdocs, %{added: [], removed: [removed_a], loaded: []}, _, ^root_doc}
    assert removed_a.reference == first_a_ref

    :ok = Map.set(folder, "b", sub_doc_b)

    assert_receive {:subdocs, %{added: [added_b], removed: [], loaded: [_loaded_b]}, _, ^root_doc}

    b_ref = added_b.reference
    assert b_ref != first_a_ref

    :ok = Map.set(folder, "a", sub_doc_a)

    assert_receive {:subdocs, %{added: [readded_a], removed: [], loaded: [_loaded_readded_a]}, _,
                    ^root_doc}

    assert Doc.guid(readded_a) == Doc.guid(sub_doc_a)
    assert readded_a.reference != first_a_ref
    assert readded_a.reference != b_ref

    :ok = Doc.demonitor_update(monitor_ref)
  end

  describe "load/1" do
    test "loading a remote subdoc emits a loaded event on the parent" do
      local = Doc.new()
      :ok = Map.set(Doc.get_map(local, "folder"), "a", Doc.new())
      {:ok, update} = Yex.encode_state_as_update(local)

      remote = Doc.new()
      {:ok, monitor_ref} = Doc.monitor_subdocs(remote)
      :ok = Yex.apply_update(remote, update)

      assert_receive {:subdocs, %{added: [_], removed: [], loaded: []}, _, ^remote}

      sub_doc = Map.fetch!(Doc.get_map(remote, "folder"), "a")
      refute Doc.should_load(sub_doc)

      assert :ok = Doc.load(sub_doc)

      assert_receive {:subdocs, %{added: [], removed: [], loaded: [loaded]}, _, ^remote}
      assert Doc.guid(loaded) == Doc.guid(sub_doc)
      assert Doc.should_load(sub_doc)

      :ok = Doc.demonitor_update(monitor_ref)
    end

    test "sets should_load on a root document" do
      doc = Doc.with_options(%Doc.Options{should_load: false})
      refute Doc.should_load(doc)

      assert :ok = Doc.load(doc)
      assert Doc.should_load(doc)
    end

    test "raises inside a transaction on the parent" do
      root_doc = Doc.new()
      folder = Doc.get_map(root_doc, "folder")
      :ok = Map.set(folder, "a", Doc.new())
      sub_doc = Map.fetch!(folder, "a")

      assert_raise Yex.TransactionAcqError, fn ->
        Doc.transaction(root_doc, fn -> Doc.load(sub_doc) end)
      end
    end
  end

  describe "destroy/1" do
    test "replaces a subdoc with a new unloaded doc in its parent" do
      root_doc = Doc.new()
      folder = Doc.get_map(root_doc, "folder")
      sub_doc = Doc.new()
      Text.insert(Doc.get_text(sub_doc, "text"), 0, "content")
      :ok = Map.set(folder, "a", sub_doc)
      {:ok, monitor_ref} = Doc.monitor_subdocs(root_doc)

      stored = Map.fetch!(folder, "a")
      assert :ok = Doc.destroy(stored)

      assert_receive {:subdocs, %{added: [added], removed: [removed], loaded: []}, _, ^root_doc}
      assert Doc.guid(added) == Doc.guid(sub_doc)
      assert Doc.guid(removed) == Doc.guid(sub_doc)

      replaced = Map.fetch!(folder, "a")
      assert replaced.reference != stored.reference
      assert Doc.guid(replaced) == Doc.guid(sub_doc)
      refute Doc.should_load(replaced)

      :ok = Doc.demonitor_update(monitor_ref)
    end

    test "drops the observers of a root document" do
      doc = Doc.new()
      text = Doc.get_text(doc, "text")
      {:ok, _} = Doc.monitor_update(doc)

      assert :ok = Doc.destroy(doc)

      Text.insert(text, 0, "after destroy")
      refute_receive {:update_v1, _, _, _}
    end

    test "raises inside a transaction on the document" do
      doc = Doc.new()

      assert_raise Yex.TransactionAcqError, fn ->
        Doc.transaction(doc, fn -> Doc.destroy(doc) end)
      end
    end
  end

  test "replacing a subdoc with another doc of the same guid hands out the new doc" do
    root_doc = Doc.new()
    folder = Doc.get_map(root_doc, "folder")
    {:ok, monitor_ref} = Doc.monitor_subdocs(root_doc)

    first = Doc.with_options(%Doc.Options{guid: "same"})
    Text.insert(Doc.get_text(first, "text"), 0, "first")
    :ok = Map.set(folder, "a", first)

    assert_receive {:subdocs, %{added: [added_first]}, _, ^root_doc}
    first_ref = Map.get(folder, "a").reference
    assert added_first.reference == first_ref

    second = Doc.with_options(%Doc.Options{guid: "same"})
    Text.insert(Doc.get_text(second, "text"), 0, "second")

    # Deleting and re-adding in one transaction keeps the guid among the parent's
    # subdocs, so a cache keyed only by guid would keep returning the first doc.
    Doc.transaction(root_doc, fn ->
      :ok = Map.delete(folder, "a")
      :ok = Map.set(folder, "a", second)
    end)

    assert_receive {:subdocs, %{added: [added_second], removed: [removed]}, _, ^root_doc}
    assert Doc.guid(added_second) == "same"
    assert removed.reference == first_ref
    assert added_second.reference != first_ref

    from_map = Map.get(folder, "a")
    assert from_map.reference == added_second.reference
    assert Text.to_string(Doc.get_text(from_map, "text")) == "second"

    :ok = Yex.Subscription.unsubscribe(monitor_ref)
  end
end
