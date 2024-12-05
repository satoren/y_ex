defmodule Yex.SharedTypeTest do
  use ExUnit.Case
  alias Yex.{SharedType, Doc}

  test "observe/2" do
    doc = Doc.new()
    assert _ref = SharedType.observe(Doc.get_text(doc, "text"), [])
    assert _ref = SharedType.observe_deep(Doc.get_text(doc, "text"), [])
  end
end
