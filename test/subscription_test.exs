defmodule Yex.SubscriptionTest do
  use ExUnit.Case
  alias Yex.{Doc, Subscription}

  setup do
    doc = Doc.new()
    {:ok, doc: doc}
  end

  describe "register/2" do
    test "registers subscription with auto-generated ref", %{doc: doc} do
      sub = %Subscription{doc: doc, reference: make_ref()}
      ref = Subscription.register(sub)
      assert is_reference(ref)
      assert Process.get(ref) == sub
    end

    test "registers subscription with provided ref", %{doc: doc} do
      sub = %Subscription{doc: doc, reference: make_ref()}
      provided_ref = make_ref()
      assert provided_ref == Subscription.register(sub, provided_ref)
      assert Process.get(provided_ref) == sub
    end
  end

  describe "unsubscribe/1" do
    test "handles non-existent subscription gracefully" do
      ref = make_ref()
      assert :ok = Subscription.unsubscribe(ref)
    end

    test "removes subscription from process dictionary", %{doc: _doc} do
      ref = make_ref()
      Process.put(ref, nil)
      assert :ok = Subscription.unsubscribe(ref)
      assert Process.get(ref) == nil
    end
  end
end
