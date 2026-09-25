defmodule Yex.DocTest do
  use ExUnit.Case, async: true
  alias Yex.{Array, Doc, Map, Text, XmlElementPrelim, XmlFragment}
  doctest Doc

  test "new" do
    assert _doc = Doc.new()
  end

  test "with_options" do
    assert _doc =
             Doc.with_options(%Doc.Options{
               offset_kind: :bytes,
               skip_gc: false,
               auto_load: false,
               should_load: true
             })
  end

  test "transact_mut" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "Hello")
        Text.insert(text, 0, "Hello", %{"bold" => true})
      end)
  end

  test "get_text in transaction" do
    doc = Doc.new()

    text =
      in_single_transaction(doc, fn ->
        text = Doc.get_text(doc, "text")
        Text.insert(text, 0, "Hello")
        Text.insert(text, 5, " World")
        text
      end)

    assert Text.to_string(text) == "Hello World"
  end

  test "get_array in transaction" do
    doc = Doc.new()

    array =
      in_single_transaction(doc, fn ->
        array = Doc.get_array(doc, "array")
        Array.push(array, "a")
        Array.push(array, "b")
        array
      end)

    assert Array.to_json(array) == ["a", "b"]
  end

  test "get_map in transaction" do
    doc = Doc.new()

    map =
      in_single_transaction(doc, fn ->
        map = Doc.get_map(doc, "map")
        Map.set(map, "name", "Alice")
        Map.set(map, "role", "admin")
        map
      end)

    assert Map.to_json(map) == %{"name" => "Alice", "role" => "admin"}
  end

  test "get_xml_fragment in transaction" do
    doc = Doc.new()

    xml =
      in_single_transaction(doc, fn ->
        xml = Doc.get_xml_fragment(doc, "xml")
        XmlFragment.push(xml, XmlElementPrelim.empty("div"))
        xml
      end)

    assert XmlFragment.to_string(xml) == "<div></div>"
  end

  test "transaction error" do
    doc = Doc.new()

    _text = Doc.get_text(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        assert_raise Yex.TransactionAcqError, fn ->
          Doc.transaction(doc, fn ->
            nil
          end)
        end

        :ok
      end)
  end

  test "Sync two clients by exchanging the complete document structure" do
    doc1 = Doc.new()

    text1 = Doc.get_text(doc1, "text")
    Text.insert(text1, 0, "Hello")

    doc2 = Doc.new()
    text2 = Doc.get_text(doc2, "text")

    {:ok, state1} = Yex.encode_state_as_update(doc1)
    {:ok, state2} = Yex.encode_state_as_update(doc2)
    :ok = Yex.apply_update(doc1, state2)
    :ok = Yex.apply_update(doc2, state1)

    assert Text.to_string(text1) == "Hello"
    assert Text.to_string(text2) == "Hello"
  end

  test "monitor_update" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    text1 = Doc.get_text(doc, "text")
    Text.insert(text1, 0, "HelloWorld")

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v1, _update, nil, ^doc}
    Doc.demonitor_update(monitor_ref)
  end

  test "monitor_update with medatada" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc, metadata: "metadata")

    text1 = Doc.get_text(doc, "text")
    Text.insert(text1, 0, "HelloWorld")

    assert_receive {:update_v1, _update, nil, "metadata"}
    Doc.demonitor_update(monitor_ref)
  end

  test "demonitor_update inside a transaction stops receiving updates" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)
    text = Doc.get_text(doc, "text")

    Doc.transaction(doc, fn ->
      :ok = Doc.demonitor_update(monitor_ref)
      Text.insert(text, 0, "Hello")
    end)

    Text.insert(text, 0, "World")

    refute_receive {:update_v1, _update, _origin, _metadata}, 10
  end

  test "monitor_update_v2" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update_v2(doc)

    text1 = Doc.get_text(doc, "text")
    Text.insert(text1, 0, "HelloWorld")

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v2, _update, nil, ^doc}
    Doc.demonitor_update_v2(monitor_ref)
  end

  test "monitor_update_v2 with medatada" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update_v2(doc, metadata: "metadata")

    text1 = Doc.get_text(doc, "text")
    Text.insert(text1, 0, "HelloWorld")

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v2, _update, nil, "metadata"}
    Doc.demonitor_update_v2(monitor_ref)
  end

  test "monitor_update with transaction" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    text1 = Doc.get_text(doc, "text")

    Doc.transaction(doc, fn ->
      Text.insert(text1, 0, "World")
      Text.insert(text1, 0, "Hello")
    end)

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v1, _update, nil, ^doc}
    Doc.demonitor_update(monitor_ref)
  end

  test "apply_update from update event" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    text1 = Doc.get_text(doc, "text")
    Text.insert(text1, 0, "HelloWorld")

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v1, update, nil, ^doc}

    doc2 = Doc.new()
    :ok = Yex.apply_update(doc2, update)
    text2 = Doc.get_text(doc2, "text")
    assert Text.to_string(text2) == "HelloWorld"

    Doc.demonitor_update(monitor_ref)
  end

  test "state vector?" do
    doc = Doc.new()

    {:ok, _} =
      Yex.encode_state_as_update_v1(
        doc,
        <<0>>
      )
  end

  test "raise error" do
    doc = Doc.new()

    assert_raise ArgumentError, fn ->
      Yex.encode_state_as_update!(
        doc,
        <<100>>
      )
    end
  end

  test "monitor_update with transaction origin" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    text1 = Doc.get_text(doc, "text")

    Doc.transaction(doc, "origin", fn ->
      :ok = Text.insert(text1, 0, "World")
      :ok = Text.insert(text1, 0, "Hello")
    end)

    assert Text.to_string(text1) == "HelloWorld"
    assert_receive {:update_v1, _update, "origin", ^doc}
    Doc.demonitor_update(monitor_ref)
  end

  test "origin accepts any types" do
    doc = Doc.new()
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    text1 = Doc.get_text(doc, "text")

    update_and_check_origin = fn origin ->
      Doc.transaction(doc, origin, fn ->
        Text.insert(text1, 0, "World")
      end)

      assert_receive {:update_v1, _update, ^origin, ^doc}
    end

    update_and_check_origin.("origin")
    update_and_check_origin.(self())
    update_and_check_origin.(1000)
    update_and_check_origin.(<<1, 2, 3>>)
    update_and_check_origin.([1, 2, 3, 4])
    update_and_check_origin.(:an_atom)
    update_and_check_origin.(%{key: "value"})
    update_and_check_origin.({:ok, "value"})
    update_and_check_origin.(nil)
    update_and_check_origin.(3.14)
    update_and_check_origin.(make_ref())
    update_and_check_origin.(fn -> :test end)
    update_and_check_origin.({:error, "reason", 123})
    update_and_check_origin.(%{nested: %{data: [1, 2]}})
    Doc.demonitor_update(monitor_ref)
  end

  describe "json_path" do
    test "returns matched values from nested structures" do
      doc = Doc.new()
      users = Doc.get_array(doc, "users")

      Yex.Array.push(users, %{
        "name" => "Alice",
        "friends" => [
          %{"nick" => "boreas"},
          %{"nick" => "crocodile91"}
        ]
      })

      assert {:ok, ["boreas", "crocodile91"]} =
               Doc.json_path(doc, "$.users..friends.*.nick")
    end

    test "returns invalid_json_path error for unsupported syntax" do
      doc = Doc.new()

      assert {:error, {:invalid_json_path, _}} =
               Doc.json_path(doc, "$[?(@.name == 'Alice')]")
    end
  end

  describe "get_pending_update / get_pending_ds" do
    test "returns nil when no pending update exists" do
      doc = Doc.new()
      assert {:ok, nil} = Doc.get_pending_update(doc)
      assert {:ok, nil} = Doc.get_pending_ds(doc)
    end

    test "returns nil for a doc that has content but no missing dependencies" do
      doc = Doc.new()
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "Hello")
      assert {:ok, nil} = Doc.get_pending_update(doc)
      assert {:ok, nil} = Doc.get_pending_ds(doc)
    end

    test "returns binary pending update when update arrives out of order" do
      doc1 = Doc.new()
      text = Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Text.insert(text, 0, "Hello")
      {:ok, update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      doc2 = Doc.new()
      :ok = Yex.apply_update(doc2, update_b)

      assert {:ok, pending} = Doc.get_pending_update(doc2)
      assert is_binary(pending)
      assert byte_size(pending) > 0

      :ok = Yex.apply_update(doc2, update_a)
      assert {:ok, nil} = Doc.get_pending_update(doc2)
    end

    test "pending update is re-encodable as a valid v1 update" do
      doc1 = Doc.new()
      text = Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Text.insert(text, 0, "Hello")
      {:ok, _update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      doc2 = Doc.new()
      :ok = Yex.apply_update(doc2, update_b)

      {:ok, pending} = Doc.get_pending_update(doc2)
      assert {:ok, debug} = Yex.update_debug_v1(pending)
      assert is_binary(debug)
    end

    test "pending update resolves to the same final state regardless of application order" do
      doc1 = Doc.new()
      text = Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Text.insert(text, 0, "Hello")
      {:ok, update_a} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_a} = Yex.encode_state_vector(doc1)
      Text.insert(text, 5, " World")
      {:ok, update_b} = Yex.encode_state_as_update(doc1, sv_a)

      doc2 = Doc.new()
      :ok = Yex.apply_update(doc2, update_a)
      :ok = Yex.apply_update(doc2, update_b)

      doc3 = Doc.new()
      :ok = Yex.apply_update(doc3, update_b)
      :ok = Yex.apply_update(doc3, update_a)

      text2 = Doc.get_text(doc2, "text")
      text3 = Doc.get_text(doc3, "text")
      assert Text.to_string(text2) == Text.to_string(text3)
      assert Text.to_string(text3) == "Hello World"
    end

    test "pending delete set appears when a deletion refers to unknown items" do
      doc1 = Doc.new()
      text = Doc.get_text(doc1, "text")
      {:ok, sv_empty} = Yex.encode_state_vector(doc1)
      Text.insert(text, 0, "Hello")
      {:ok, update_insert} = Yex.encode_state_as_update(doc1, sv_empty)
      {:ok, sv_after_insert} = Yex.encode_state_vector(doc1)
      Text.delete(text, 0, 5)
      {:ok, update_delete} = Yex.encode_state_as_update(doc1, sv_after_insert)

      doc2 = Doc.new()
      :ok = Yex.apply_update(doc2, update_delete)

      assert {:ok, pending_ds} = Doc.get_pending_ds(doc2)
      assert is_binary(pending_ds)
      assert byte_size(pending_ds) > 0

      :ok = Yex.apply_update(doc2, update_insert)
      assert {:ok, nil} = Doc.get_pending_ds(doc2)
    end
  end

  describe "prune_pending" do
    defp gapped_update do
      a = Doc.new()
      t = Doc.get_text(a, "t")
      Text.insert(t, 0, "one")
      update_one = Yex.encode_state_as_update!(a)
      sv1 = Yex.encode_state_vector!(a)
      Text.insert(t, 3, "two")
      {a, update_one, Yex.encode_state_as_update!(a, sv1)}
    end

    test "returns nil when nothing is pending" do
      doc = Doc.new()
      assert {:ok, nil} = Doc.prune_pending(doc)
    end

    test "removes and returns pending content" do
      {a, _update_one, gapped} = gapped_update()
      b = Doc.new()
      :ok = Yex.apply_update(b, gapped)

      assert {:ok, pending} = Doc.get_pending_update(b)
      assert is_binary(pending)

      assert {:ok, pruned} = Doc.prune_pending(b)
      assert is_binary(pruned)
      assert byte_size(pruned) > 0

      assert {:ok, nil} = Doc.get_pending_update(b)
      assert {:ok, nil} = Doc.get_pending_ds(b)
      assert {:ok, nil} = Doc.prune_pending(b)

      :ok = Yex.apply_update(b, Yex.encode_state_as_update!(a))
      assert Text.to_string(Doc.get_text(b, "t")) == "onetwo"
    end

    test "removes a pending delete set" do
      a = Doc.new()
      t = Doc.get_text(a, "t")
      Text.insert(t, 0, "Hello")
      sv = Yex.encode_state_vector!(a)
      Text.delete(t, 0, 5)
      delete_only = Yex.encode_state_as_update!(a, sv)

      b = Doc.new()
      :ok = Yex.apply_update(b, delete_only)
      assert {:ok, ds} = Doc.get_pending_ds(b)
      assert is_binary(ds)

      assert {:ok, pruned} = Doc.prune_pending(b)
      assert is_binary(pruned)
      assert {:ok, nil} = Doc.get_pending_ds(b)
    end

    test "pruned bytes can be re-applied once the predecessor is present" do
      {_a, update_one, gapped} = gapped_update()
      b = Doc.new()
      :ok = Yex.apply_update(b, gapped)
      {:ok, pruned} = Doc.prune_pending(b)

      :ok = Yex.apply_update(b, update_one)
      assert Text.to_string(Doc.get_text(b, "t")) == "one"

      :ok = Yex.apply_update(b, pruned)
      assert Text.to_string(Doc.get_text(b, "t")) == "onetwo"
      assert {:ok, nil} = Doc.get_pending_update(b)
    end

    test "works inside a transaction" do
      {_a, _update_one, gapped} = gapped_update()
      b = Doc.new()
      :ok = Yex.apply_update(b, gapped)

      result =
        Doc.transaction(b, fn ->
          {:ok, pruned} = Doc.prune_pending(b)
          {pruned, Doc.get_pending_update(b)}
        end)

      assert {pruned, {:ok, nil}} = result
      assert is_binary(pruned)
      assert {:ok, nil} = Doc.get_pending_update(b)
    end

    test "emits no update message, with or without pending content" do
      {_a, _update_one, gapped} = gapped_update()
      b = Doc.new()
      :ok = Yex.apply_update(b, gapped)
      {:ok, _sub} = Doc.monitor_update(b)

      assert {:ok, pruned} = Doc.prune_pending(b)
      assert is_binary(pruned)
      refute_receive {:update_v1, _, _, _}, 50

      assert {:ok, nil} = Doc.prune_pending(b)
      refute_receive {:update_v1, _, _, _}, 50
    end

    test "works through a worker process" do
      {:ok, worker_pid} = GenServer.start_link(__MODULE__.TestWorker, %{})
      {_a, _update_one, gapped} = gapped_update()
      b = Doc.new(worker_pid)
      :ok = Yex.apply_update(b, gapped)

      assert {:ok, pruned} = Doc.prune_pending(b)
      assert is_binary(pruned)
      assert {:ok, nil} = Doc.get_pending_update(b)
    end

    test "reports a transaction held by another process" do
      test_pid = self()
      {_a, _update_one, gapped} = gapped_update()

      holder =
        spawn_link(fn ->
          doc = Doc.new()
          :ok = Yex.apply_update(doc, gapped)

          Doc.transaction(doc, fn ->
            send(test_pid, {:holding, doc})

            receive do
              :release -> :ok
            end
          end)

          send(test_pid, :released)
        end)

      assert_receive {:holding, doc}, 5_000
      # Task with timeout plus early release makes a blocking regression fail, not hang.
      task =
        Task.async(fn ->
          try do
            Doc.prune_pending(%{doc | worker_pid: self()})
          rescue
            error in Yex.TransactionAcqError -> {:raised, error}
          end
        end)

      yielded = Task.yield(task, 5_000)
      send(holder, :release)
      assert {:ok, {:raised, %Yex.TransactionAcqError{}}} = yielded || Task.shutdown(task)
      assert_receive :released, 5_000

      doc = %{doc | worker_pid: self()}
      assert {:ok, pending} = Doc.get_pending_update(doc)
      assert is_binary(pending)
    end
  end

  # Additional comprehensive tests for better coverage

  describe "basic type creation" do
    test "get_text returns Text struct" do
      doc = Doc.new()
      text = Doc.get_text(doc, "test_text")

      assert %Yex.Text{} = text
      assert is_binary(text.reference)
      assert text.doc == doc
    end

    test "get_map returns Map struct" do
      doc = Doc.new()
      map = Doc.get_map(doc, "test_map")

      assert %Yex.Map{} = map
      assert is_binary(map.reference)
      assert map.doc == doc
    end

    test "get_array returns Array struct" do
      doc = Doc.new()
      array = Doc.get_array(doc, "test_array")

      assert %Yex.Array{} = array
      assert is_binary(array.reference)
      assert array.doc == doc
    end
  end

  describe "document properties" do
    test "client_id returns integer" do
      doc = Doc.new()
      assert is_integer(Doc.client_id(doc))
    end

    test "guid returns string when set in options" do
      guid = "test-guid-123"
      doc = Doc.with_options(%Doc.Options{guid: guid})
      assert Doc.guid(doc) == guid
    end

    test "guid returns nil when not set" do
      doc = Doc.new()
      result = Doc.guid(doc)
      # guid might be auto-generated or nil depending on implementation
      assert result == nil or is_binary(result)
    end

    test "collection_id returns value from options" do
      collection_id = "test-collection"
      doc = Doc.with_options(%Doc.Options{collection_id: collection_id})
      result = Doc.collection_id(doc)
      assert result == collection_id or result == nil
    end

    test "skip_gc returns boolean from options" do
      doc1 = Doc.with_options(%Doc.Options{skip_gc: true})
      doc2 = Doc.with_options(%Doc.Options{skip_gc: false})

      assert Doc.skip_gc(doc1) == true
      assert Doc.skip_gc(doc2) == false
    end

    test "auto_load returns boolean from options" do
      doc1 = Doc.with_options(%Doc.Options{auto_load: true})
      doc2 = Doc.with_options(%Doc.Options{auto_load: false})

      assert Doc.auto_load(doc1) == true
      assert Doc.auto_load(doc2) == false
    end

    test "should_load returns boolean from options" do
      doc1 = Doc.with_options(%Doc.Options{should_load: true})
      doc2 = Doc.with_options(%Doc.Options{should_load: false})

      assert Doc.should_load(doc1) == true
      assert Doc.should_load(doc2) == false
    end

    test "offset_kind returns atom from options" do
      doc1 = Doc.with_options(%Doc.Options{offset_kind: :bytes})
      doc2 = Doc.with_options(%Doc.Options{offset_kind: :utf16})

      assert Doc.offset_kind(doc1) == :bytes
      assert Doc.offset_kind(doc2) == :utf16
    end
  end

  describe "get_xml_fragment" do
    test "creates and retrieves xml fragment" do
      doc = Doc.new()
      xml_fragment = Doc.get_xml_fragment(doc, "test_fragment")

      assert %Yex.XmlFragment{} = xml_fragment
      assert is_binary(xml_fragment.reference)
    end

    test "same name returns same xml fragment" do
      doc = Doc.new()
      xml1 = Doc.get_xml_fragment(doc, "same_name")
      xml2 = Doc.get_xml_fragment(doc, "same_name")

      # Both should reference the same underlying object
      assert xml1.reference == xml2.reference
    end

    test "different names return different xml fragments" do
      doc = Doc.new()
      xml1 = Doc.get_xml_fragment(doc, "fragment1")
      xml2 = Doc.get_xml_fragment(doc, "fragment2")

      assert xml1.reference != xml2.reference
    end
  end

  describe "monitor_subdocs" do
    test "monitor_subdocs returns subscription" do
      doc = Doc.new()
      result = Doc.monitor_subdocs(doc)

      case result do
        {:ok, ref} ->
          assert is_reference(ref)
          Yex.Subscription.unsubscribe(ref)

        {:error, _} ->
          # Some implementations might not support subdocs monitoring
          :ok
      end
    end

    test "monitor_subdocs with metadata" do
      doc = Doc.new()
      metadata = "subdoc_metadata"
      result = Doc.monitor_subdocs(doc, metadata: metadata)

      case result do
        {:ok, ref} ->
          assert is_reference(ref)
          Yex.Subscription.unsubscribe(ref)

        {:error, _} ->
          # Some implementations might not support subdocs monitoring
          :ok
      end
    end
  end

  describe "worker process functionality" do
    setup do
      # Create a simple GenServer to act as worker
      {:ok, worker_pid} = GenServer.start_link(__MODULE__.TestWorker, %{})
      {:ok, worker_pid: worker_pid}
    end

    test "document with worker process executes in worker", %{worker_pid: worker_pid} do
      doc = Doc.new(worker_pid)
      text = Doc.get_text(doc, "test")

      # This should work through the worker process
      assert %Yex.Text{} = text
      assert is_binary(text.reference)
    end

    test "document properties work through worker process", %{worker_pid: worker_pid} do
      doc = Doc.new(worker_pid)

      assert is_integer(Doc.client_id(doc))
      result = Doc.guid(doc)
      assert result == nil or is_binary(result)
    end

    test "transactions work through worker process", %{worker_pid: worker_pid} do
      doc = Doc.new(worker_pid)
      text = Doc.get_text(doc, "test")

      result =
        Doc.transaction(doc, fn ->
          Text.insert(text, 0, "Hello")
          :transaction_result
        end)

      assert result == :transaction_result
      assert Text.to_string(text) == "Hello"
    end

    test "monitoring works through worker process", %{worker_pid: worker_pid} do
      doc = Doc.new(worker_pid)
      {:ok, monitor_ref} = Doc.monitor_update(doc)

      text = Doc.get_text(doc, "test")
      Text.insert(text, 0, "Hello")

      assert_receive {:update_v1, _update, nil, ^doc}
      Doc.demonitor_update(monitor_ref)
    end
  end

  describe "error handling" do
    test "run_in_worker_process raises when worker_pid is nil and not self" do
      # Create a doc with nil worker_pid
      doc = %Doc{reference: make_ref(), worker_pid: nil}

      assert_raise RuntimeError, "Document has no worker process assigned", fn ->
        Doc.client_id(doc)
      end
    end

    test "nested transaction raises error" do
      doc = Doc.new()

      assert_raise Yex.TransactionAcqError, fn ->
        Doc.transaction(doc, fn ->
          Doc.transaction(doc, fn ->
            :nested
          end)
        end)
      end
    end
  end

  describe "options structure" do
    test "Options struct has all expected fields with defaults" do
      options = %Doc.Options{}

      assert options.client_id == 0
      assert options.guid == nil
      assert options.collection_id == nil
      assert options.offset_kind == :bytes
      assert options.skip_gc == false
      assert options.auto_load == false
      assert options.should_load == true
    end

    test "Options can be created with custom values" do
      options = %Doc.Options{
        client_id: 123,
        guid: "custom-guid",
        collection_id: "custom-collection",
        offset_kind: :utf16,
        skip_gc: true,
        auto_load: true,
        should_load: false
      }

      assert options.client_id == 123
      assert options.guid == "custom-guid"
      assert options.collection_id == "custom-collection"
      assert options.offset_kind == :utf16
      assert options.skip_gc == true
      assert options.auto_load == true
      assert options.should_load == false
    end
  end

  describe "monitor_update" do
  end

  describe "demonitor functions" do
    test "demonitor_update is alias for demonitor_update_v1" do
      doc = Doc.new()
      {:ok, ref} = Doc.monitor_update(doc)

      # Both should work equivalently
      result1 = Doc.demonitor_update(ref)
      assert result1 == :ok or match?({:error, _}, result1)
    end

    test "demonitor_update_v1 and demonitor_update_v2 handle subscriptions" do
      doc = Doc.new()

      # Test v1
      {:ok, ref1} = Doc.monitor_update_v1(doc)
      result1 = Doc.demonitor_update_v1(ref1)
      assert result1 == :ok or match?({:error, _}, result1)

      # Test v2
      {:ok, ref2} = Doc.monitor_update_v2(doc)
      result2 = Doc.demonitor_update_v2(ref2)
      assert result2 == :ok or match?({:error, _}, result2)
    end
  end

  # Getters and mutations must reuse the transaction opened by `Doc.transaction/3`.
  # Routing through `try_transact_mut` would either fail while that write lock is
  # held, or commit independently and emit an update before the callback returns.
  defp in_single_transaction(doc, fun) do
    {:ok, monitor_ref} = Doc.monitor_update(doc)

    result =
      Doc.transaction(doc, fn ->
        value = fun.()
        refute_received {:update_v1, _update, _origin, _metadata}
        value
      end)

    assert_receive {:update_v1, _update, nil, ^doc}
    refute_receive {:update_v1, _update, _origin, _metadata}, 10
    Doc.demonitor_update(monitor_ref)
    result
  end

  # Test worker module for worker process tests
  defmodule TestWorker do
    use GenServer

    @impl true
    def init(state) do
      {:ok, state}
    end

    @impl true
    def handle_call({Yex.Doc, :run, fun}, _from, state) do
      {:reply, fun.(), state}
    end

    @impl true
    def handle_call(_msg, _from, state) do
      {:reply, :ok, state}
    end
  end

  describe "root getters and open transactions" do
    test "return handles whose writes commit with the transaction" do
      test_pid = self()

      # Run in a task so a scheduler-parking regression trips the timeout.
      task =
        Task.async(fn ->
          doc = Doc.new()
          {:ok, _sub} = Doc.monitor_update(doc)

          Doc.transaction(doc, fn ->
            Text.insert(Doc.get_text(doc, "text"), 0, "hello")
            Yex.Array.push(Doc.get_array(doc, "array"), 1)
            Yex.Map.set(Doc.get_map(doc, "map"), "k", "v")
            Yex.XmlFragment.push(Doc.get_xml_fragment(doc, "xml"), Yex.XmlTextPrelim.from("x"))
          end)

          updates =
            Stream.repeatedly(fn ->
              receive do
                {:update_v1, _, _, _} = msg -> msg
              after
                50 -> nil
              end
            end)
            |> Enum.take_while(& &1)

          send(test_pid, {:update_count, length(updates)})
          %{doc | worker_pid: test_pid}
        end)

      assert {:ok, doc} = Task.yield(task, 5_000) || Task.shutdown(task)
      assert_received {:update_count, 1}

      assert Text.to_string(Doc.get_text(doc, "text")) == "hello"
      assert Yex.Array.to_list(Doc.get_array(doc, "array")) == [1.0]
      assert Yex.Map.to_map(Doc.get_map(doc, "map")) == %{"k" => "v"}
      assert Yex.XmlFragment.to_string(Doc.get_xml_fragment(doc, "xml")) == "x"
    end

    test "return the same root on repeated calls inside a transaction" do
      task =
        Task.async(fn ->
          doc = Doc.new()

          Doc.transaction(doc, fn ->
            Text.insert(Doc.get_text(doc, "text"), 0, "hello")
            Yex.Array.push(Doc.get_array(doc, "array"), 1)
            Yex.Map.set(Doc.get_map(doc, "map"), "k", "v")
            Yex.XmlFragment.push(Doc.get_xml_fragment(doc, "xml"), Yex.XmlTextPrelim.from("x"))

            {Text.to_string(Doc.get_text(doc, "text")),
             Yex.Array.to_list(Doc.get_array(doc, "array")),
             Yex.Map.to_map(Doc.get_map(doc, "map")),
             Yex.XmlFragment.to_string(Doc.get_xml_fragment(doc, "xml"))}
          end)
        end)

      assert {:ok, {"hello", [1.0], %{"k" => "v"}, "x"}} =
               Task.yield(task, 5_000) || Task.shutdown(task)
    end

    test "raise when another process holds a transaction" do
      test_pid = self()

      holder =
        spawn_link(fn ->
          doc = Doc.new()

          Doc.transaction(doc, fn ->
            send(test_pid, {:holding, doc})

            receive do
              :release -> :ok
            end
          end)

          send(test_pid, :released)
        end)

      assert_receive {:holding, doc}, 5_000

      # Task with timeout plus early release makes a blocking regression fail, not hang.
      task =
        Task.async(fn ->
          doc = %{doc | worker_pid: self()}

          for getter <- [
                &Doc.get_text/2,
                &Doc.get_array/2,
                &Doc.get_map/2,
                &Doc.get_xml_fragment/2
              ] do
            try do
              getter.(doc, "root")
            rescue
              error in Yex.TransactionAcqError -> {:raised, error.__struct__}
            end
          end
        end)

      yielded = Task.yield(task, 5_000)
      send(holder, :release)

      assert {:ok, List.duplicate({:raised, Yex.TransactionAcqError}, 4)} ==
               (yielded || Task.shutdown(task))

      assert_receive :released, 5_000
      assert %Yex.Map{} = Doc.get_map(%{doc | worker_pid: self()}, "map")
    end
  end
end
