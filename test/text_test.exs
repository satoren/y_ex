defmodule Yex.TextTest do
  use ExUnit.Case
  alias Yex.{Doc, Text}
  doctest Doc

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
end
