defmodule Yex.SnapshotTest do
  use ExUnit.Case, async: true

  describe "snapshot / encode_state_from_snapshot" do
    test "Yex.Snapshot.encode_state_v1/1 and encode_state_v2/1 are available" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)

      assert {:ok, update_v1} = Yex.Snapshot.encode_state_v1(snapshot)
      assert {:ok, update_v2} = Yex.Snapshot.encode_state_v2(snapshot)
      assert is_binary(update_v1)
      assert is_binary(update_v2)
    end

    test "Snapshot.encode_state_v1 restores point-in-time state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 5, " World")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "Snapshot.encode_state_v2 restores point-in-time state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 5, " World")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v2(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "snapshot encoding returns encoding_exception when GC is enabled" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "Hello")
      {:ok, snapshot} = Yex.snapshot(doc)

      assert {:error, {:encoding_exception, _}} =
               Yex.Snapshot.encode_state_v1(snapshot)

      assert {:error, {:encoding_exception, _}} =
               Yex.Snapshot.encode_state_v2(snapshot)
    end

    test "snapshot APIs work inside explicit transaction context" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      update_from_snapshot =
        Yex.Doc.transaction(doc, fn ->
          Yex.Text.insert(text, 0, "Hello")
          {:ok, snapshot} = Yex.snapshot(doc)
          Yex.Text.insert(text, 5, " World")
          {:ok, update} = Yex.Snapshot.encode_state_v1(snapshot)
          update
        end)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "Hello"
      assert Yex.Text.to_string(text) == "Hello World"
    end

    test "Snapshot.encode_state_v1 produces parseable v1 update" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abc")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 3, "def")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)
      assert {:ok, debug} = Yex.update_debug_v1(update_from_snapshot)
      assert is_binary(debug)
      assert byte_size(debug) > 0
    end

    test "Snapshot.encode_state_v2 produces parseable v2 update" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abc")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.insert(text, 3, "def")

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)
      assert {:ok, debug} = Yex.update_debug_v2(update_from_snapshot)
      assert is_binary(debug)
      assert byte_size(debug) > 0
    end

    test "empty snapshot can be encoded and restores empty state" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")
      {:ok, snapshot} = Yex.snapshot(doc)

      Yex.Text.insert(text, 0, "newer")
      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == ""
      assert Yex.Text.to_string(text) == "newer"
    end

    test "snapshot before delete restores pre-delete content" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      text = Yex.Doc.get_text(doc, "text")

      Yex.Text.insert(text, 0, "abcdef")
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Text.delete(text, 2, 3)

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v1(snapshot)

      restored = Yex.Doc.new()
      restored_text = Yex.Doc.get_text(restored, "text")
      :ok = Yex.apply_update_v1(restored, update_from_snapshot)

      assert Yex.Text.to_string(restored_text) == "abcdef"
      assert Yex.Text.to_string(text) == "abf"
    end

    test "snapshot works for array shared type" do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      array = Yex.Doc.get_array(doc, "arr")

      Yex.Array.insert_list(array, 0, [1, 2])
      {:ok, snapshot} = Yex.snapshot(doc)
      Yex.Array.insert_list(array, 2, [3, 4])

      {:ok, update_from_snapshot} = Yex.Snapshot.encode_state_v2(snapshot)

      restored = Yex.Doc.new()
      restored_array = Yex.Doc.get_array(restored, "arr")
      :ok = Yex.apply_update_v2(restored, update_from_snapshot)

      assert Yex.Array.to_list(restored_array) == [1.0, 2.0]
      assert Yex.Array.to_list(array) == [1.0, 2.0, 3.0, 4.0]
    end
  end
end
