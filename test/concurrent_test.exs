defmodule DocWorker do
  use Yex.DocServer

  @impl true
  def init(_arg, state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:get_doc, _from, %{doc: doc} = state) do
    {:reply, doc, state}
  end
end

defmodule Yex.DocConcurrentTest do
  use ExUnit.Case
  alias Yex.{Doc, Text, Map}

  setup do
    {:ok, pid} = DocWorker.start_link([])
    doc = GenServer.call(pid, :get_doc)
    %{pid: pid, doc: doc}
  end

  test "concurrent transactions", %{doc: doc} do
    text1 = Doc.get_text(doc, "text")

    tasks =
      for _ <- 1..10 do
        Task.async(fn ->
          Doc.get_text(doc, "text")

          Doc.transaction(doc, "origin", fn ->
            Text.insert(text1, 0, "World")

            Process.sleep(1)
          end)
        end)
      end

    Task.await_many(tasks)
  end

  test "transaction result", %{doc: doc} do
    assert "result" ==
             Doc.transaction(doc, "origin", fn ->
               "result"
             end)
  end

  describe "propagate errors to caller" do
    test "miss match key type", %{doc: doc} do
      map = Doc.get_map(doc, "map")
      assert_raise FunctionClauseError, fn -> Map.set(map, 0, "Hello") end
    end

    test "Key not found", %{doc: doc} do
      map = Doc.get_map(doc, "map")

      assert_raise ArgumentError, "Key not found", fn ->
        Map.fetch!(map, "key3")
      end
    end

    test "Map has been deleted", %{doc: doc} do
      map = Doc.get_map(doc, "map")
      Map.set(map, "key", Yex.MapPrelim.from(%{"key" => "Hello"}))
      m = Map.fetch!(map, "key")
      Map.delete(map, "key")

      assert_raise Yex.DeletedSharedTypeError, "Map has been deleted", fn ->
        Map.set(m, "key", "Hello")
      end
    end

    test "raise error in transaction", %{doc: doc} do
      assert_raise RuntimeError, "Error", fn ->
        Doc.transaction(doc, "origin", fn ->
          raise "Error"
        end)
      end
    end

    test "transaction error", %{doc: doc} do
      :ok =
        Doc.transaction(doc, fn ->
          # nif panic
          assert_raise RuntimeError, fn ->
            Doc.transaction(doc, fn ->
              nil
            end)
          end

          :ok
        end)
    end
  end
end
