defmodule Yex.SharedTypeTest do
  use ExUnit.Case
  alias Yex.{SharedType, Doc, Text, Output}

  setup do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")
    {:ok, doc: doc, text: text}
  end

  describe "observe/2" do
    test "basic observation", %{text: text} do
      ref = SharedType.observe(text, [])
      assert is_reference(ref)
    end

    test "observation with default options", %{text: text} do
      ref = SharedType.observe(text)
      assert is_reference(ref)
    end

    test "observation with metadata", %{doc: doc, text: text} do
      metadata = %{test: "metadata"}
      ref = SharedType.observe(text, metadata: metadata)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      assert_receive {:observe_event, ^ref, _event, _origin, ^metadata}
    end

    test "unobserve stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe(text, [])
      :ok = SharedType.unobserve(ref)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      refute_receive {:observe_event, ^ref, _event, _origin, _metadata}
    end
  end

  describe "observe_deep/2" do
    test "deep observation with default options", %{text: text} do
      ref = SharedType.observe_deep(text)
      assert is_reference(ref)
    end

    test "deep observation with metadata", %{doc: doc, text: text} do
      metadata = %{test: "deep_metadata"}
      ref = SharedType.observe_deep(text, metadata: metadata)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      assert_receive {:observe_deep_event, ^ref, _events, _origin, ^metadata}
    end

    test "unobserve_deep stops receiving events", %{doc: doc, text: text} do
      ref = SharedType.observe_deep(text, [])
      :ok = SharedType.unobserve_deep(ref)

      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "hello")
      end)

      refute_receive {:observe_deep_event, ^ref, _events, _origin, _metadata}
    end
  end

  describe "Output protocol" do
    test "as_prelim returns a TextPrelim for Text", %{text: text} do
      assert %Yex.TextPrelim{} = Output.as_prelim(text)
    end
  end
end
