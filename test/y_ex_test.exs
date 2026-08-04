defmodule YexTest do
  use ExUnit.Case, async: true
  doctest Yex

  describe "apply_update" do
    test "apply_update" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update(doc1)
      {:ok, state2} = Yex.encode_state_as_update(doc2)
      :ok = Yex.apply_update(doc1, state2)
      :ok = Yex.apply_update(doc2, state1)
    end

    test "apply_update_v2" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update_v2(doc1)
      {:ok, state2} = Yex.encode_state_as_update_v2(doc2)
      :ok = Yex.apply_update_v2(doc1, state2)
      :ok = Yex.apply_update_v2(doc2, state1)
    end
  end

  describe "merge_updates" do
    test "merge_updates_v1" do
      doc1 = Yex.Doc.new()
      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update(doc1)
      {:ok, state2} = Yex.encode_state_as_update(doc2)
      {:ok, merged} = Yex.merge_updates_v1([state1, state2])

      doc3 = Yex.Doc.new()
      text3 = Yex.Doc.get_text(doc3, "text")
      :ok = Yex.apply_update_v1(doc3, merged)

      assert Yex.Text.to_string(text3) == "Hello"
    end

    test "merge_updates_v2" do
      doc1 = Yex.Doc.new()
      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update_v2(doc1)
      {:ok, state2} = Yex.encode_state_as_update_v2(doc2)
      {:ok, merged} = Yex.merge_updates_v2([state1, state2])

      doc3 = Yex.Doc.new()
      text3 = Yex.Doc.get_text(doc3, "text")
      :ok = Yex.apply_update_v2(doc3, merged)

      assert Yex.Text.to_string(text3) == "Hello"
    end
  end

  describe "update_debug" do
    test "update_debug_v1" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "Hello")

      {:ok, update} = Yex.encode_state_as_update_v1(doc)
      {:ok, debug} = Yex.update_debug_v1(update)

      assert is_binary(debug)
      assert String.length(debug) > 0
      assert {:error, {:encoding_exception, _}} = Yex.update_debug_v1(<<1, 2, 3>>)
    end

    test "update_debug_v2" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "Hello")

      {:ok, update} = Yex.encode_state_as_update_v2(doc)
      {:ok, debug} = Yex.update_debug_v2(update)

      assert is_binary(debug)
      assert String.length(debug) > 0
      assert {:error, {:encoding_exception, _}} = Yex.update_debug_v2(<<1, 2, 3>>)
    end
  end

  describe "encode_state_as_update" do
    test "encode_state_as_update" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update(doc)
    end

    test "encode_state_as_update!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_as_update!(doc))

      assert_raise ArgumentError, fn -> Yex.encode_state_as_update!(doc, <<11>>) end
    end

    test "encode_state_as_update_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update_v2(doc)
    end

    test "encode_diff_and_state_vector_v1 matches separate encode calls" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "t")
      Yex.Text.insert(text, 0, "abc")
      {:ok, remote_sv} = Yex.encode_state_vector(Yex.Doc.new())

      {:ok, diff, sv} = Yex.encode_diff_and_state_vector_v1(doc, remote_sv)
      {:ok, diff2} = Yex.encode_state_as_update(doc, remote_sv)
      {:ok, sv2} = Yex.encode_state_vector(doc)

      assert diff == diff2
      assert sv == sv2
    end
  end

  describe "encode_state_vector" do
    test "encode_state_vector" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector(doc)
    end

    test "encode_state_vector!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_vector!(doc))
    end

    test "encode_state_vector_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector_v2(doc)
    end
  end

  describe "get_pending_update / get_pending_ds" do
    test "returns nil when no pending update exists" do
      doc = Yex.Doc.new()
      assert {:ok, nil} = Yex.get_pending_update(doc)
      assert {:ok, nil} = Yex.get_pending_ds(doc)
    end

    test "returns nil for a doc that has content but no missing dependencies" do
      doc = Yex.Doc.new()
      text = Yex.Doc.get_text(doc, "text")
      Yex.Text.insert(text, 0, "Hello")
      assert {:ok, nil} = Yex.get_pending_update(doc)
      assert {:ok, nil} = Yex.get_pending_ds(doc)
    end

    test "returns binary pending update when update arrives out of order" do
      # Apply the second chunk of an update before the first to create a pending update.
      doc1 = Yex.Doc.new()
      text = Yex.Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 0, "Hello")
      {:ok, update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      # doc2 receives update_b (depends on update_a) before update_a → pending
      doc2 = Yex.Doc.new()
      :ok = Yex.apply_update(doc2, update_b)

      assert {:ok, pending} = Yex.get_pending_update(doc2)
      assert is_binary(pending)
      assert byte_size(pending) > 0

      # After applying the missing update, pending clears
      :ok = Yex.apply_update(doc2, update_a)
      assert {:ok, nil} = Yex.get_pending_update(doc2)
    end

    test "pending update is re-encodable as a valid v1 update" do
      doc1 = Yex.Doc.new()
      text = Yex.Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 0, "Hello")
      {:ok, _update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      doc2 = Yex.Doc.new()
      :ok = Yex.apply_update(doc2, update_b)

      {:ok, pending} = Yex.get_pending_update(doc2)
      # The pending binary must itself be a parseable v1 update
      assert {:ok, debug} = Yex.update_debug_v1(pending)
      assert is_binary(debug)
    end

    test "pending update resolves to the same final state regardless of application order" do
      doc1 = Yex.Doc.new()
      text = Yex.Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 0, "Hello")
      {:ok, update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      # doc2: correct order
      doc2 = Yex.Doc.new()
      :ok = Yex.apply_update(doc2, update_a)
      :ok = Yex.apply_update(doc2, update_b)

      # doc3: reversed order (b first → pending, then a resolves it)
      doc3 = Yex.Doc.new()
      :ok = Yex.apply_update(doc3, update_b)
      :ok = Yex.apply_update(doc3, update_a)

      text2 = Yex.Doc.get_text(doc2, "text")
      text3 = Yex.Doc.get_text(doc3, "text")
      assert Yex.Text.to_string(text2) == Yex.Text.to_string(text3)
      assert Yex.Text.to_string(text3) == "Hello World"
    end

    test "pending delete set appears when a deletion refers to unknown items" do
      doc1 = Yex.Doc.new()
      text = Yex.Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Yex.Text.insert(text, 0, "Hello")
      {:ok, update_insert} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_after_insert} = Yex.encode_state_vector(doc1)
      Yex.Text.delete(text, 0, 5)
      {:ok, update_delete} = Yex.encode_state_as_update(doc1, sv_after_insert)

      # doc2 gets the delete before the insert → pending delete set
      doc2 = Yex.Doc.new()
      :ok = Yex.apply_update(doc2, update_delete)

      assert {:ok, pending_ds} = Yex.get_pending_ds(doc2)
      assert is_binary(pending_ds)
      assert byte_size(pending_ds) > 0

      # Applying the insert resolves both the pending update and delete set
      :ok = Yex.apply_update(doc2, update_insert)
      assert {:ok, nil} = Yex.get_pending_ds(doc2)
    end
  end
end
