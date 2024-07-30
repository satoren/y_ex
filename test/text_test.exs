defmodule Yex.TextTest do
  use ExUnit.Case
  alias Yex.{Doc, Text}
  doctest Text

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

      assert [%{"insert" => "4"}, %{"attributes" => %{"bold" => true}, "insert" => "5"}] ==
               Text.to_delta(text)
    end
  end

  test "Retain" do
    doc = Doc.new()

    text = Doc.get_text(doc, "text")

    delta = [
      %{
        "retain" => 1
      },
      %{
        "delete" => 3
      }
    ]

    Text.insert(text, 0, "12345")
    Text.apply_delta(text, delta)
    assert "15" == Text.to_string(text)

    assert [%{"insert" => "15"}] ==
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
             %{"insert" => "1"},
             %{"attributes" => %{"bold" => true}, "insert" => "abc"},
             %{"insert" => "2xyz3"}
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

    assert [%{"insert" => "12345", "attributes" => %{"italic" => true}}, %{"insert" => "6"}] ==
             Text.to_delta(text)
  end
end
