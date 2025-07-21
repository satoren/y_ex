defmodule Yex.SubdocsTest do
  use ExUnit.Case

  alias Yex.{
    Doc,
    Text,
    Array,
    Map,
    XmlElement,
    XmlText,
    XmlFragment,
    XmlElementPrelim,
    XmlTextPrelim
  }

  test "new" do
    root_doc = Doc.new()
    folder = Doc.get_map(root_doc, "text")
    Doc.monitor_subdocs(root_doc)

    sub_doc = Doc.new()
    sub_doc_text = Doc.get_text(sub_doc, "subdoc-text")
    Text.insert(sub_doc_text, 0, "some initial content")
    Map.set(folder, "my-document.txt", sub_doc)

    assert_receive {:subdocs, %{added: added, loaded: loaded, removed: []}, _, ^root_doc}

    assert length(added) == 1
    assert length(loaded) == 1
    assert Doc.guid(sub_doc) == Doc.guid(hd(added))
    assert Doc.guid(sub_doc) == Doc.guid(hd(loaded))

    Doc
  end
end
