defmodule YexTest do
  use ExUnit.Case
  import Mock
  doctest Yex

  describe "apply_update" do
    test "apply_update" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update(doc1)
      {:ok, state2} = Yex.encode_state_as_update(doc2)
      :ok = Yex.apply_update(doc1, state2)
      :ok = Yex.apply_update(doc2, state1)
    end

    test "apply_update_v2" do
      doc1 = Yex.Doc.new()

      text1 = Yex.Doc.get_text(doc1, "text")
      Yex.Text.insert(text1, 0, "Hello")

      doc2 = Yex.Doc.new()
      Yex.Doc.get_text(doc2, "text")

      {:ok, state1} = Yex.encode_state_as_update_v2(doc1)
      {:ok, state2} = Yex.encode_state_as_update_v2(doc2)
      :ok = Yex.apply_update_v2(doc1, state2)
      :ok = Yex.apply_update_v2(doc2, state1)
    end
  end

  describe "encode_state_as_update" do
    test "encode_state_as_update" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update(doc)
    end

    test "encode_state_as_update!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_as_update!(doc))

      assert_raise ArgumentError, fn -> Yex.encode_state_as_update!(doc, <<11>>) end
    end

    test "encode_state_as_update_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_as_update_v2(doc)
    end

    test "encode_state_as_update! raise error" do
      doc = Yex.Doc.new()

      with_mock Yex.Nif,
        encode_state_as_update_v1: fn _, _, _ -> {:error, :some_error} end do
        assert_raise RuntimeError, fn -> Yex.encode_state_as_update!(doc) end
      end
    end
  end

  describe "encode_state_vector" do
    test "encode_state_vector" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector(doc)
    end

    test "encode_state_vector!" do
      doc = Yex.Doc.new()
      assert is_binary(Yex.encode_state_vector!(doc))
    end

    test "encode_state_vector_v2" do
      doc = Yex.Doc.new()
      {:ok, _binary} = Yex.encode_state_vector_v2(doc)
    end

    test "encode_state_vector! raise error" do
      doc = Yex.Doc.new()

      with_mock Yex.Nif,
        encode_state_vector_v1: fn _, _ -> {:error, :some_error} end do
        assert_raise RuntimeError, fn -> Yex.encode_state_vector!(doc) end
      end
    end
  end
end
