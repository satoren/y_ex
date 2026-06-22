defmodule Yex.AnyTest do
  use ExUnit.Case, async: true
  alias Yex.{Doc, Text, Map}

  describe "number" do
    test "All numbers that can be safely converted to f64 according to JavaScript specifications will be floats" do
      doc = Yex.Doc.new()
      map = Yex.Doc.get_map(doc, "map")
      Yex.Map.set(map, "key", 1)
      assert Yex.Map.get(map, "key") == {:ok, 1}
    end

    test "safe integer boundaries are floats" do
      doc = Yex.Doc.new()
      map = Yex.Doc.get_map(doc, "map")
      max_safe = 9_007_199_254_740_991
      min_safe = -9_007_199_254_740_991
      over_max = 9_007_199_254_740_992
      under_min = -9_007_199_254_740_992

      Yex.Map.set(map, "max_safe", max_safe)
      Yex.Map.set(map, "min_safe", min_safe)
      Yex.Map.set(map, "over_max", over_max)
      Yex.Map.set(map, "under_min", under_min)

      assert Yex.Map.get(map, "max_safe") == {:ok, max_safe}
      assert Yex.Map.get(map, "min_safe") == {:ok, min_safe}
      assert Yex.Map.get(map, "over_max") == {:ok, over_max}
      assert Yex.Map.get(map, "under_min") == {:ok, under_min}
    end
  end
end
