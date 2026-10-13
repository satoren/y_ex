defmodule Yex.Yjs do
  @moduledoc false
  # Drives the real Yjs (test/support/yjs/bridge.mjs on Node.js) from tests, so that
  # y_ex can be checked against the JavaScript implementation it is meant to talk to.
  #
  # `eval!/3` runs `code` as the body of an async JavaScript function that receives
  # `Y`, `syncProtocol`, `awarenessProtocol`, `encoding`, `decoding`, `args` and `ctx`,
  # and returns what it returns. Bytes go in as `{:bytes, binary}` (a bare binary is a
  # string) and arrive as `Uint8Array`; a `Uint8Array` comes back as a binary.
  use GenServer

  @dir Path.expand("yjs", __DIR__)
  @script Path.join(@dir, "bridge.mjs")

  @doc """
  Returns `:ok` when Node.js and the npm packages of the bridge are installed,
  otherwise `{:error, reason}`.
  """
  def check do
    cond do
      System.find_executable("node") == nil ->
        {:error, "node is not on PATH"}

      not File.dir?(Path.join([@dir, "node_modules", "yjs"])) ->
        {:error, "run `npm ci --prefix test/support/yjs`"}

      true ->
        :ok
    end
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  def eval!(server, code, args \\ %{}) do
    case GenServer.call(server, {:eval, %{code: code, args: encode(args)}}, 30_000) do
      {:ok, result} -> result
      {:error, message} -> raise "Yjs raised:\n#{message}"
    end
  end

  @doc "Forgets everything the snippets stored in `ctx`."
  def reset!(server) do
    {:ok, nil} = GenServer.call(server, {:eval, %{reset: true}}, 30_000)
    :ok
  end

  @impl true
  def init(_opts) do
    port =
      Port.open({:spawn_executable, System.find_executable("node")}, [
        :binary,
        :exit_status,
        packet: 4,
        args: [@script],
        cd: @dir
      ])

    {:ok, %{port: port, waiting: :queue.new()}}
  end

  @impl true
  def handle_call({:eval, request}, from, %{port: port, waiting: waiting} = state) do
    Port.command(port, Jason.encode_to_iodata!(request))
    {:noreply, %{state | waiting: :queue.in(from, waiting)}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, waiting: waiting} = state) do
    {{:value, from}, waiting} = :queue.out(waiting)

    reply =
      case Jason.decode!(data) do
        %{"ok" => result} -> {:ok, decode(result)}
        %{"error" => message} -> {:error, message}
      end

    GenServer.reply(from, reply)
    {:noreply, %{state | waiting: waiting}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    {:stop, {:node_exited, status}, state}
  end

  defp encode({:bytes, binary}) when is_binary(binary), do: %{"$bytes" => Base.encode64(binary)}
  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  defp encode(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, encode(value)} end)

  defp encode(value), do: value

  defp decode(%{"$bytes" => base64}), do: Base.decode64!(base64)
  defp decode(%{"$bigint" => integer}), do: String.to_integer(integer)
  defp decode(list) when is_list(list), do: Enum.map(list, &decode/1)
  defp decode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, decode(value)} end)
  defp decode(value), do: value
end
