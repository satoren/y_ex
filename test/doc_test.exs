defmodule Yex.DocTest do
  use ExUnit.Case
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
      Text.insert(text1, 0, "World")
      Text.insert(text1, 0, "Hello")
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
    Doc.demonitor_update(monitor_ref)
  end
end
