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
end
