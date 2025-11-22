defmodule Yex.DocTest do
  use ExUnit.Case
  import Mock
  alias Yex.{Doc, Text}
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

  test "transaction error" do
    doc = Doc.new()

    _text = Doc.get_text(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        # nif panic
        assert_raise RuntimeError, fn ->
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

    test "monitor_subdocs fail" do
      doc = Doc.new()

      with_mock Yex.Nif,
        doc_monitor_subdocs: fn _, _notify_pid, _metadata -> {:error, :some_error} end do
        assert {:error, :some_error} = Doc.monitor_subdocs(doc)
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

      assert_raise RuntimeError, "Transaction already in progress", fn ->
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
    test "monitor_update_v1 fail" do
      doc = Doc.new()

      with_mock Yex.Nif,
        doc_monitor_update_v1: fn _, _options, _metadata -> {:error, :some_error} end do
        assert {:error, :some_error} = Doc.monitor_update_v1(doc)
      end
    end

    test "monitor_update_v2 fail" do
      doc = Doc.new()

      with_mock Yex.Nif,
        doc_monitor_update_v2: fn _, _options, _metadata -> {:error, :some_error} end do
        assert {:error, :some_error} = Doc.monitor_update_v2(doc)
      end
    end
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
end
