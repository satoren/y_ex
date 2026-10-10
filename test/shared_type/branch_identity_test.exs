defmodule Yex.BranchIdentityTest do
  use ExUnit.Case, async: true

  alias Yex.{
    Array,
    ArrayPrelim,
    Doc,
    Map,
    MapPrelim,
    SharedType,
    Text,
    TextPrelim,
    UndoManager,
    WeakLink,
    XmlElement,
    XmlElementPrelim,
    XmlFragment,
    XmlText,
    XmlTextPrelim
  }

  doctest SharedType

  defp sync(from, to) do
    :ok = Yex.apply_update(to, Yex.encode_state_as_update!(from))
  end

  defp sync_v2(from, to) do
    {:ok, update} = Yex.encode_state_as_update_v2(from)
    :ok = Yex.apply_update_v2(to, update)
  end

  # Hides the value's type from the compiler, which otherwise warns that a call
  # deliberately made with the wrong struct can never match.
  defp untyped(term), do: :erlang.binary_to_term(:erlang.term_to_binary(term))

  defp doc_with_client(client_id) do
    Doc.with_options(%Doc.Options{client_id: client_id})
  end

  describe "branch_id/1" do
    test "a root type is identified by its name" do
      doc = Doc.new()

      assert SharedType.branch_id(Doc.get_text(doc, "t")) == {:root, "t"}
      assert SharedType.branch_id(Doc.get_map(doc, "m")) == {:root, "m"}
      assert SharedType.branch_id(Doc.get_array(doc, "a")) == {:root, "a"}
      assert SharedType.branch_id(Doc.get_xml_fragment(doc, "x")) == {:root, "x"}
      assert SharedType.branch_id(Doc.get_text(doc, "名前")) == {:root, "名前"}
    end

    test "a nested type is identified by the client and clock of the item that created it" do
      doc = Doc.new()
      client = Doc.client_id(doc)
      map = Doc.get_map(doc, "m")
      array = Doc.get_array(doc, "a")
      fragment = Doc.get_xml_fragment(doc, "x")

      nested_map = Map.set_and_get(map, "map", MapPrelim.from(%{}))
      nested_text = Array.insert_and_get(array, 0, TextPrelim.from("hi"))
      element = XmlFragment.insert_and_get(fragment, 0, XmlElementPrelim.empty("p"))
      xml_text = XmlElement.insert_and_get(element, 0, XmlTextPrelim.from("x"))
      weak = Map.set_and_get(map, "link", Map.link(map, "map"))

      for type <- [nested_map, nested_text, element, xml_text, weak] do
        assert {:nested, ^client, clock} = SharedType.branch_id(type)
        assert is_integer(clock) and clock >= 0
      end

      ids = Enum.map([nested_map, nested_text, element, xml_text, weak], &SharedType.branch_id/1)
      assert length(Enum.uniq(ids)) == 5
    end

    test "two structs for the same type have the same id" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      Map.set(map, "nested", MapPrelim.from(%{}))

      assert SharedType.branch_id(Map.fetch!(map, "nested")) ==
               SharedType.branch_id(Map.fetch!(map, "nested"))
    end

    test "works on a deleted type" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)

      Map.delete(map, "nested")

      assert SharedType.branch_id(nested) == id
    end

    test "does not need the document's worker process" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)

      # The doc's worker is this test process, which is blocked in Task.await and
      # never answers, so a call routed through the worker would time out.
      assert Task.async(fn -> SharedType.branch_id(nested) end) |> Task.await(1000) == id
      refute_received {:"$gen_call", _, {Yex.Doc, :run, _}}
    end

    test "rejects a prelim" do
      assert_raise FunctionClauseError, fn ->
        SharedType.branch_id(untyped(TextPrelim.from("x")))
      end
    end
  end

  describe "alive?/1" do
    test "a root type is alive" do
      doc = Doc.new()
      assert SharedType.alive?(Doc.get_text(doc, "t"))
    end

    test "a nested type is not alive after it or an ancestor is deleted" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      parent = Map.set_and_get(map, "parent", MapPrelim.from(%{}))
      child = Map.set_and_get(parent, "child", TextPrelim.from("x"))
      sibling = Map.set_and_get(map, "sibling", ArrayPrelim.from([]))

      assert SharedType.alive?(parent)
      assert SharedType.alive?(child)

      Map.delete(map, "sibling")
      refute SharedType.alive?(sibling)

      Map.delete(map, "parent")
      refute SharedType.alive?(parent)
      refute SharedType.alive?(child)
    end

    test "joins an open transaction" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")

      Doc.transaction(doc, fn ->
        nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
        assert SharedType.alive?(nested)
        Map.delete(map, "nested")
        refute SharedType.alive?(nested)
      end)
    end

    test "is false exactly when using the type raises after a remote deletion" do
      doc_a = Doc.new()
      doc_b = Doc.new()
      Map.set(Doc.get_map(doc_a, "m"), "nested", TextPrelim.from("x"))
      sync(doc_a, doc_b)

      nested_b = Map.fetch!(Doc.get_map(doc_b, "m"), "nested")
      assert SharedType.alive?(nested_b)
      assert Text.to_string(nested_b) == "x"

      Map.delete(Doc.get_map(doc_a, "m"), "nested")
      sync(doc_a, doc_b)

      refute SharedType.alive?(nested_b)
      assert_raise Yex.DeletedSharedTypeError, fn -> Text.insert(nested_b, 0, "y") end
    end

    test "can be called from a process other than the doc's worker" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))

      task = Task.async(fn -> SharedType.alive?(nested) end)
      assert_receive {:"$gen_call", from, {Yex.Doc, :run, fun}}, 1000
      GenServer.reply(from, fun.())
      assert Task.await(task, 1000) == true
    end

    test "rejects a prelim" do
      assert_raise FunctionClauseError, fn -> SharedType.alive?(untyped(TextPrelim.from("x"))) end
    end
  end

  describe "resolve/2" do
    test "resolves a root type to the same struct" do
      doc = Doc.new()
      text = Doc.get_text(doc, "t")

      assert {:ok, %Text{} = resolved} = SharedType.resolve(doc, {:root, "t"})
      assert resolved == text
      assert SharedType.branch_id(resolved) == {:root, "t"}
    end

    test "resolves a unicode root name" do
      doc = Doc.new()
      Text.insert(Doc.get_text(doc, "名前"), 0, "x")

      assert {:ok, %Text{} = text} = SharedType.resolve(doc, {:root, "名前"})
      assert Text.to_string(text) == "x"
    end

    test "resolves a nested type of every kind" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      fragment = Doc.get_xml_fragment(doc, "x")

      nested_map = Map.set_and_get(map, "map", MapPrelim.from(%{"k" => "v"}))
      nested_array = Map.set_and_get(map, "array", ArrayPrelim.from([1]))
      nested_text = Map.set_and_get(map, "text", TextPrelim.from("hi"))
      element = XmlFragment.insert_and_get(fragment, 0, XmlElementPrelim.empty("p"))
      xml_text = XmlElement.insert_and_get(element, 0, XmlTextPrelim.from("x"))
      weak = Map.set_and_get(map, "link", Map.link(map, "map"))

      for {type, module} <- [
            {nested_map, Map},
            {nested_array, Array},
            {nested_text, Text},
            {element, XmlElement},
            {xml_text, XmlText},
            {weak, WeakLink}
          ] do
        id = SharedType.branch_id(type)
        assert {:ok, %^module{} = resolved} = SharedType.resolve(doc, id)
        assert resolved == type
        assert SharedType.branch_id(resolved) == id
      end

      {:ok, resolved_map} = SharedType.resolve(doc, SharedType.branch_id(nested_map))
      assert Map.to_map(resolved_map) == %{"k" => "v"}
    end

    test "a missing root is not found and is not created" do
      doc = Doc.new()
      Text.insert(Doc.get_text(doc, "t"), 0, "x")
      before = Yex.encode_state_as_update!(doc)

      assert SharedType.resolve(doc, {:root, "nope"}) == {:error, :not_found}
      assert SharedType.resolve(doc, {:root, "nope"}) == {:error, :not_found}
      assert Yex.encode_state_as_update!(doc) == before
    end

    test "an unknown nested id is not found" do
      doc = Doc.new()
      client = Doc.client_id(doc)
      Text.insert(Doc.get_text(doc, "t"), 0, "abc")

      assert SharedType.resolve(doc, {:nested, client + 1, 0}) == {:error, :not_found}
      assert SharedType.resolve(doc, {:nested, client, 3}) == {:error, :not_found}
    end

    test "the largest client and clock values are accepted" do
      doc = Doc.new()

      assert SharedType.resolve(doc, {:nested, 2 ** 53 - 1, 0}) == {:error, :not_found}
      assert SharedType.resolve(doc, {:nested, 1, 2 ** 32 - 1}) == {:error, :not_found}
    end

    test "a type deleted and garbage collected is deleted" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)

      Map.delete(map, "nested")

      assert SharedType.resolve(doc, id) == {:error, :deleted}
    end

    test "a deleted type is deleted when garbage collection is off" do
      doc = Doc.with_options(%Doc.Options{skip_gc: true})
      map = Doc.get_map(doc, "m")
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)

      Map.delete(map, "nested")

      assert SharedType.resolve(doc, id) == {:error, :deleted}
    end

    test "joins an open transaction" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")

      Doc.transaction(doc, fn ->
        nested = Map.set_and_get(map, "nested", MapPrelim.from(%{}))
        id = SharedType.branch_id(nested)
        assert {:ok, ^nested} = SharedType.resolve(doc, id)

        Map.delete(map, "nested")
        assert SharedType.resolve(doc, id) == {:error, :deleted}
      end)
    end

    test "resolves a nested type created by a remote update, v1 and v2" do
      doc_a = Doc.new()
      nested = Map.set_and_get(Doc.get_map(doc_a, "m"), "nested", MapPrelim.from(%{"k" => 1}))
      id = SharedType.branch_id(nested)

      for sync_fun <- [&sync/2, &sync_v2/2] do
        doc_b = Doc.new()
        assert SharedType.resolve(doc_b, id) == {:error, :not_found}

        sync_fun.(doc_a, doc_b)

        assert {:ok, %Map{} = resolved} = SharedType.resolve(doc_b, id)
        assert Map.to_map(resolved) == %{"k" => 1}
        assert SharedType.branch_id(resolved) == id
      end
    end

    test "a root created only by a remote update is untyped until claimed" do
      doc_a = Doc.new()
      Map.set(Doc.get_map(doc_a, "m"), "k", "v")
      doc_b = Doc.new()
      sync(doc_a, doc_b)

      assert SharedType.resolve(doc_b, {:root, "m"}) == {:error, :untyped}

      Doc.get_map(doc_b, "m")
      assert {:ok, %Map{} = map} = SharedType.resolve(doc_b, {:root, "m"})
      assert Map.to_map(map) == %{"k" => "v"}
    end

    test "a type whose update is still pending is not found" do
      doc_a = Doc.new()
      parent = Map.set_and_get(Doc.get_map(doc_a, "m"), "parent", MapPrelim.from(%{}))
      sv = Yex.encode_state_vector!(doc_a)
      child = Map.set_and_get(parent, "child", MapPrelim.from(%{}))
      id = SharedType.branch_id(child)

      # Only the second update: the child's parent is missing, so it stays pending.
      doc_b = Doc.new()
      :ok = Yex.apply_update(doc_b, Yex.encode_state_as_update!(doc_a, sv))
      assert {:ok, pending} = Yex.get_pending_update(doc_b)
      assert is_binary(pending)

      assert SharedType.resolve(doc_b, id) == {:error, :not_found}
    end

    test "a type deleted by a remote update is deleted on the receiving side" do
      doc_a = Doc.new()
      map_a = Doc.get_map(doc_a, "m")
      nested = Map.set_and_get(map_a, "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)
      doc_b = Doc.new()
      sync(doc_a, doc_b)
      {:ok, nested_b} = SharedType.resolve(doc_b, id)

      Map.delete(map_a, "nested")
      sync(doc_a, doc_b)

      assert SharedType.resolve(doc_b, id) == {:error, :deleted}
      refute SharedType.alive?(nested_b)
    end

    test "undoing a deletion restores the type under a new id" do
      doc = Doc.new()
      map = Doc.get_map(doc, "m")
      {:ok, undo_manager} = UndoManager.new(doc, map)
      nested = Map.set_and_get(map, "nested", MapPrelim.from(%{"k" => "v"}))
      old_id = SharedType.branch_id(nested)
      UndoManager.stop_capturing(undo_manager)

      Map.delete(map, "nested")
      UndoManager.undo(undo_manager)

      refute SharedType.alive?(nested)
      assert SharedType.resolve(doc, old_id) == {:error, :deleted}

      restored = Map.fetch!(map, "nested")
      assert SharedType.alive?(restored)
      assert Map.to_map(restored) == %{"k" => "v"}
      assert SharedType.branch_id(restored) != old_id
    end

    test "an id that names content other than a shared type is deleted" do
      doc = Doc.new()
      Text.insert(Doc.get_text(doc, "t"), 0, "abc")

      assert SharedType.resolve(doc, {:nested, Doc.client_id(doc), 1}) == {:error, :deleted}
    end

    test "an id from an unrelated document is not found" do
      # Default options: each doc gets a random client id.
      doc_a = Doc.new()
      nested = Map.set_and_get(Doc.get_map(doc_a, "m"), "nested", MapPrelim.from(%{}))
      doc_b = Doc.new()
      Map.set(Doc.get_map(doc_b, "m"), "nested", MapPrelim.from(%{}))

      assert SharedType.resolve(doc_b, SharedType.branch_id(nested)) == {:error, :not_found}
    end

    test "a document sharing the client id answers deleted once it has integrated that clock" do
      doc_a = doc_with_client(7)
      doc_b = doc_with_client(7)
      nested = Map.set_and_get(Doc.get_map(doc_a, "m"), "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)

      assert SharedType.resolve(doc_b, id) == {:error, :not_found}

      Text.insert(Doc.get_text(doc_b, "t"), 0, "abcdef")

      assert SharedType.resolve(doc_b, id) == {:error, :deleted}
    end

    test "an id round trips through external term format" do
      doc_a = Doc.new()
      nested = Map.set_and_get(Doc.get_map(doc_a, "m"), "nested", TextPrelim.from("hello"))
      stored = :erlang.term_to_binary(SharedType.branch_id(nested))
      update = Yex.encode_state_as_update!(doc_a)

      result =
        Task.async(fn ->
          doc = Doc.new()
          :ok = Yex.apply_update(doc, update)
          {:ok, text} = SharedType.resolve(doc, :erlang.binary_to_term(stored))
          Text.to_string(text)
        end)
        |> Task.await(1000)

      assert result == "hello"
    end

    test "a type inside a subdocument resolves against the subdocument only" do
      # Same client id in both, so only the stores tell them apart. The padding puts
      # the nested type at a clock past the parent's one item (the subdoc at clock 0).
      root = doc_with_client(7)
      sub = doc_with_client(7)
      Text.insert(Doc.get_text(sub, "pad"), 0, "abcde")
      nested = Map.set_and_get(Doc.get_map(sub, "m"), "nested", MapPrelim.from(%{}))
      id = SharedType.branch_id(nested)
      assert id == {:nested, 7, 5}
      Map.set(Doc.get_map(root, "docs"), "sub", sub)

      assert {:ok, %Map{}} = SharedType.resolve(sub, id)
      assert SharedType.resolve(root, id) == {:error, :not_found}

      # A store that does hold the subdoc's blocks resolves the same id.
      replica = Doc.new()
      sync(sub, replica)
      assert {:ok, %Map{}} = SharedType.resolve(replica, id)
    end

    test "can be called from a process other than the doc's worker" do
      doc = Doc.new()
      Doc.get_text(doc, "t")

      task = Task.async(fn -> SharedType.resolve(doc, {:root, "t"}) end)
      assert_receive {:"$gen_call", from, {Yex.Doc, :run, fun}}, 1000
      GenServer.reply(from, fun.())
      assert {:ok, %Text{}} = Task.await(task, 1000)
    end

    test "raises on a malformed id" do
      doc = Doc.new()

      for bad <- [
            {:root, <<0xFF>>},
            {:root, :atom},
            {:nested, -1, 0},
            {:nested, 2 ** 53, 0},
            {:nested, 1, 2 ** 32},
            {:other, 1},
            "x"
          ] do
        assert_raise ArgumentError, fn -> SharedType.resolve(doc, bad) end
      end
    end
  end
end
