defmodule Yex.TextTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, TextPrelim, SharedType}
  doctest Text
  doctest TextPrelim

  test "transaction" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    :ok =
      Doc.transaction(doc, fn ->
        Text.insert(text, 0, "Hello")
        Text.insert(text, 0, "Hello", %{"bold" => true})
      end)

    assert "HelloHello" == Text.to_string(text)
    assert 10 == Text.length(text)
  end

  describe "Delta format" do
    test "Delete" do
      doc = Doc.new()

      text = Doc.get_text(doc, "text")

      Text.insert(text, 0, "1234")
      Text.insert(text, 5, "5", %{"bold" => true})

      delta = [
        %{
          "delete" => 3
        }
      ]

      Text.apply_delta(text, delta)
      assert "45" == Text.to_string(text)

      assert [%{insert: "4"}, %{attributes: %{"bold" => true}, insert: "5"}] ==
               Text.to_delta(text)
    end
  end

  test "Retain" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    delta = [
      %{
        retain: 1
      },
      %{
        delete: 3
      }
    ]

    Text.insert(text, 0, "12345")
    Text.apply_delta(text, delta)
    assert "15" == Text.to_string(text)

    assert [%{insert: "15"}] ==
             Text.to_delta(text)
  end

  test "Insert" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    delta = [
      %{
        "retain" => 1
      },
      %{
        "insert" => "abc",
        "attributes" => %{"bold" => true}
      },
      %{
        "retain" => 1
      },
      %{
        "insert" => "xyz"
      }
    ]

    Text.insert(text, 0, "123")
    Text.apply_delta(text, delta)

    assert [
             %{insert: "1"},
             %{insert: "abc", attributes: %{"bold" => true}},
             %{insert: "2xyz3"}
           ] ==
             Text.to_delta(text)
  end

  test "Retain (on Y.Text)" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    delta = [
      %{
        "retain" => 5,
        "attributes" => %{"italic" => true}
      }
    ]

    Text.insert(text, 0, "123456")
    Text.apply_delta(text, delta)

    assert [%{insert: "12345", attributes: %{"italic" => true}}, %{insert: "6"}] ==
             Text.to_delta(text)
  end

  test "delete" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    delta = [
      %{
        "retain" => 3,
        "attributes" => %{"italic" => true}
      }
    ]

    Text.insert(text, 0, "123456")
    Text.apply_delta(text, delta)
    Text.delete(text, 2, 2)

    assert [%{insert: "12", attributes: %{"italic" => true}}, %{insert: "56"}] ==
             Text.to_delta(text)
  end

  test "delete with minus" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    Text.insert(text, 0, "123456")

    assert "123456" == Text.to_string(text)
    assert :ok == Text.delete(text, -1, 1)
    assert "12345" == Text.to_string(text)
  end

  test "format" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    Text.insert(text, 0, "123456")
    Text.format(text, 1, 3, %{"bold" => true})

    assert [%{insert: "1"}, %{insert: "234", attributes: %{"bold" => true}}, %{insert: "56"}] ==
             Text.to_delta(text)
  end

  test "compare" do
    doc = Doc.new()

    text1 = Doc.get_text(doc, "text")
    text2 = Doc.get_text(doc, "text")

    assert text1 == text2
    text3 = Doc.get_text(doc, "text2")

    assert text1 != text3
  end

  describe "observe" do
    test "set " do
      doc = Doc.new()

      text = Doc.get_text(doc, "text")

      ref = SharedType.observe(text)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Text.insert(text, 0, "Hello")
          Text.insert(text, 6, " World", %{"bold" => true})
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.TextEvent{
                        target: ^text,
                        delta: [
                          %{insert: "Hello"},
                          %{attributes: %{"bold" => true}, insert: " World"}
                        ]
                      }, "origin_value", nil}
    end

    test "delete " do
      doc = Doc.new()

      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "Hello World")

      ref = SharedType.observe(text)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Text.delete(text, 3, 4)
        end)

      assert_receive {:observe_event, ^ref,
                      %Yex.TextEvent{
                        target: ^text,
                        delta: [%{retain: 3}, %{delete: 4}]
                      }, "origin_value", nil}
    end

    test "unobserve" do
      doc = Doc.new()

      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "Hello World")

      ref = SharedType.observe(text)
      assert :ok = SharedType.unobserve(ref)

      :ok =
        Doc.transaction(doc, "origin_value", fn ->
          Text.delete(text, 3, 4)
        end)

      refute_receive {:observe_event, ^ref, %Yex.TextEvent{}, _}

      # noop but return ok
      assert :ok = SharedType.unobserve(make_ref())
    end
  end

  test "observe_deep" do
    doc = Doc.new()
    text = Doc.get_text(doc, "text")

    Text.insert(text, 0, "Hello World")

    ref = Text.observe_deep(text)

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Text.insert(text, 0, "Hello")
        Text.insert(text, 5, " World")
      end)

    assert_receive {:observe_deep_event, ^ref,
                    [
                      %Yex.TextEvent{
                        path: [],
                        target: ^text,
                        delta: [%{insert: "Hello World"}]
                      }
                    ], "origin_value", nil}
  end

  test "unobserve_deep" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    ref = SharedType.observe_deep(text)
    assert :ok = SharedType.unobserve_deep(ref)

    :ok =
      Doc.transaction(doc, "origin_value", fn ->
        Text.insert(text, 0, "Hello")
        Text.insert(text, 6, " World")
      end)

    refute_receive {:observe_deep_event, _, %Yex.TextEvent{}, _, _}

    # noop but return ok
    assert :ok = SharedType.unobserve_deep(make_ref())
  end
end
