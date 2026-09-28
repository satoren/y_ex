defmodule Yex.SubscriptionTest do
  use ExUnit.Case, async: true
  alias Yex.{Doc, SharedType, Subscription, Text, UndoManager}

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

    test "stops delivering events, inside and outside a transaction", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      {:ok, update_sub} = Doc.monitor_update(doc)
      observe_sub = SharedType.observe(text)
      deep_sub = SharedType.observe_deep(text)

      assert :ok = Subscription.unsubscribe(update_sub)

      Doc.transaction(doc, fn ->
        assert :ok = Subscription.unsubscribe(observe_sub)
        assert :ok = Subscription.unsubscribe(deep_sub)
      end)

      Text.insert(text, 0, "a")
      refute_receive {:update_v1, _, _, _}, 10
      refute_receive {:observe_event, _, _, _, _}, 10
      refute_receive {:observe_deep_event, _, _, _, _}, 10

      {:ok, _} = Doc.monitor_update(doc)
      SharedType.observe(text)
      Text.insert(text, 0, "b")
      assert_receive {:update_v1, _, _, _}
      assert_receive {:observe_event, _, _, _, _}
    end
  end

  describe "garbage collected subscriptions and undo managers" do
    # Their destructors run on whichever scheduler thread frees them. Taking the document
    # store there would make the worker's concurrent operations fail with
    # Yex.TransactionAcqError.
    test "do not make concurrent operations on the document fail", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      test_pid = self()

      # Set up one at a time: each holder acts as the document's worker while subscribing.
      holders =
        for _ <- 1..100 do
          pid =
            spawn(fn ->
              doc = %{doc | worker_pid: self()}
              text = %{text | doc: doc}
              {:ok, _} = Doc.monitor_update(doc)
              SharedType.observe(text)
              SharedType.observe_deep(text)
              {:ok, _} = UndoManager.new(doc, text)
              send(test_pid, :subscribed)

              receive do
                :exit -> :ok
              end
            end)

          assert_receive :subscribed, 5_000
          pid
        end

      for pid <- holders, do: send(pid, :exit)

      for _ <- 1..2_000 do
        Text.insert(text, 0, "x")
        Doc.get_map(doc, "map")
        Text.to_string(text)
      end

      assert Text.length(text) == 2_000

      {:ok, _} = Doc.monitor_update(doc)
      Text.insert(text, 0, "y")
      assert_receive {:update_v1, _, _, _}
    end
  end
end
