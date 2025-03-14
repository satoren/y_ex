defmodule Yex.EventTest do
  use ExUnit.Case
  alias Yex.Doc
  alias Yex.{ArrayEvent, MapEvent, TextEvent, XmlEvent, XmlTextEvent}

  setup do
    doc = Doc.new()
    {:ok, doc: doc}
  end

  describe "ArrayEvent" do
    test "creates event with insert change", %{doc: doc} do
      array = Doc.get_array(doc, "array")

      event = %ArrayEvent{
        path: [0],
        target: array,
        change: %{insert: ["value"]}
      }

      assert event.path == [0]
      assert event.target == array
      assert event.change == %{insert: ["value"]}
    end

    test "creates event with delete change", %{doc: doc} do
      array = Doc.get_array(doc, "array")

      event = %ArrayEvent{
        path: [1],
        target: array,
        change: %{delete: 2}
      }

      assert event.path == [1]
      assert event.target == array
      assert event.change == %{delete: 2}
    end

    test "creates event with empty change", %{doc: doc} do
      array = Doc.get_array(doc, "array")

      event = %ArrayEvent{
        path: [0],
        target: array,
        change: %{}
      }

      assert event.path == [0]
      assert event.target == array
      assert event.change == %{}
    end
  end

  describe "MapEvent" do
    test "creates event with add action", %{doc: doc} do
      map = Doc.get_map(doc, "map")

      event = %MapEvent{
        path: ["key"],
        target: map,
        keys: %{"key" => %{action: :add, new_value: "value"}}
      }

      assert event.path == ["key"]
      assert event.target == map
      assert event.keys == %{"key" => %{action: :add, new_value: "value"}}
    end

    test "creates event with delete action", %{doc: doc} do
      map = Doc.get_map(doc, "map")

      event = %MapEvent{
        path: ["key"],
        target: map,
        keys: %{"key" => %{action: :delete, old_value: "value"}}
      }

      assert event.path == ["key"]
      assert event.target == map
      assert event.keys == %{"key" => %{action: :delete, old_value: "value"}}
    end

    test "creates event with update action", %{doc: doc} do
      map = Doc.get_map(doc, "map")

      event = %MapEvent{
        path: ["key"],
        target: map,
        keys: %{"key" => %{action: :update, old_value: "old", new_value: "new"}}
      }

      assert event.path == ["key"]
      assert event.target == map
      assert event.keys == %{"key" => %{action: :update, old_value: "old", new_value: "new"}}
    end

    test "creates event with multiple keys", %{doc: doc} do
      map = Doc.get_map(doc, "map")

      event = %MapEvent{
        path: ["key"],
        target: map,
        keys: %{
          "key1" => %{action: :add, new_value: "value1"},
          "key2" => %{action: :delete, old_value: "value2"},
          "key3" => %{action: :update, old_value: "old3", new_value: "new3"}
        }
      }

      assert event.path == ["key"]
      assert event.target == map

      assert event.keys == %{
               "key1" => %{action: :add, new_value: "value1"},
               "key2" => %{action: :delete, old_value: "value2"},
               "key3" => %{action: :update, old_value: "old3", new_value: "new3"}
             }
    end
  end

  describe "TextEvent" do
    test "creates event with delta", %{doc: doc} do
      text = Doc.get_text(doc, "text")
      delta = [%{insert: "Hello"}]

      event = %TextEvent{
        path: [0],
        target: text,
        delta: delta
      }

      assert event.path == [0]
      assert event.target == text
      assert event.delta == delta
    end

    test "creates event with complex delta", %{doc: doc} do
      text = Doc.get_text(doc, "text")

      delta = [
        %{insert: "Hello"},
        %{insert: " ", attributes: %{"bold" => true}},
        %{insert: "World", attributes: %{"italic" => true}}
      ]

      event = %TextEvent{
        path: [0],
        target: text,
        delta: delta
      }

      assert event.path == [0]
      assert event.target == text
      assert event.delta == delta
    end
  end

  describe "XmlEvent" do
    test "creates event with delta and keys", %{doc: doc} do
      xml = Doc.get_xml_fragment(doc, "xml")
      delta = [%{insert: "<p>"}]

      event = %XmlEvent{
        path: [0],
        target: xml,
        delta: delta,
        keys: %{insert: ["attr"]}
      }

      assert event.path == [0]
      assert event.target == xml
      assert event.delta == delta
      assert event.keys == %{insert: ["attr"]}
    end

    test "creates event with complex delta and keys", %{doc: doc} do
      xml = Doc.get_xml_fragment(doc, "xml")

      delta = [
        %{insert: "<div>"},
        %{insert: "Hello", attributes: %{"bold" => true}},
        %{insert: "</div>"}
      ]

      event = %XmlEvent{
        path: [0],
        target: xml,
        delta: delta,
        keys: %{delete: 2}
      }

      assert event.path == [0]
      assert event.target == xml
      assert event.delta == delta
      assert event.keys == %{delete: 2}
    end
  end

  describe "XmlTextEvent" do
    test "creates event with delta", %{doc: doc} do
      text = Doc.get_text(doc, "xml_text")
      delta = [%{insert: "text"}]

      event = %XmlTextEvent{
        path: [0],
        target: text,
        delta: delta
      }

      assert event.path == [0]
      assert event.target == text
      assert event.delta == delta
    end

    test "creates event with complex delta", %{doc: doc} do
      text = Doc.get_text(doc, "xml_text")

      delta = [
        %{insert: "Hello"},
        %{insert: " ", attributes: %{"bold" => true}},
        %{insert: "World", attributes: %{"italic" => true}}
      ]

      event = %XmlTextEvent{
        path: [0],
        target: text,
        delta: delta
      }

      assert event.path == [0]
      assert event.target == text
      assert event.delta == delta
    end
  end
end
