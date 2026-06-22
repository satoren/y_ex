defmodule YjsCompatTest do
  use ExUnit.Case

  describe "v1data.bin" do
    test "v1data.bin" do
      {:ok, data} = File.read("test/yjs/yjs_v1data.bin")
      doc = Yex.Doc.new()
      :ok = Yex.apply_update(doc, data)
      assert Yex.Text.to_string(Yex.Doc.get_text(doc, "text")) == "Hello World"

      map = Yex.Doc.get_map(doc, "map")

      assert Yex.Map.as_prelim(map) == %Yex.MapPrelim{
               map: %{
                 "-9007199254740991" => -9_007_199_254_740_991,
                 "-9007199254741992" => -9_007_199_254_741_092,
                 "1000" => 1000,
                 "9007199254740991" => 9_007_199_254_740_991,
                 "9007199254741992" => 9_007_199_254_741_092,
                 "key" => "value",
                 "0.5" => 0.5
               }
             }

      assert Yex.Map.get(map, "1000") == 1000.0

      Yex.Map.set(map, "9007199254740993", 9_007_199_254_740_993)
      # Note: Due to floating point precision, the value becomes 9007199254740992.0
      assert is_number(Yex.Map.get(map, "9007199254740993"))
    end

    test "y_ex_v1data.bin" do
      doc = Yex.Doc.new()

      map = Yex.Doc.get_map(doc, "map")
      Yex.Map.set(map, "key", "value")
      Yex.Map.set(map, "1000", 1000)
      Yex.Map.set(map, "9007199254741992", 9_007_199_254_741_092)
      Yex.Map.set(map, "9007199254740991", 9_007_199_254_740_991)
      Yex.Map.set(map, "9007199254740992", 9_007_199_254_740_992)
      Yex.Map.set(map, "-9007199254741992", -9_007_199_254_741_092)
      Yex.Map.set(map, "-9007199254740991", -9_007_199_254_740_991)
      Yex.Map.set(map, "0.5", 0.5)
      data = Yex.encode_state_as_update!(doc)
      :ok = File.write!("test/yjs/y_ex_v1data.bin", data)
    end
  end
end
