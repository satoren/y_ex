defmodule Yex.Buffer do
  @moduledoc """
  Binary data stored as a byte buffer, which Yjs exposes as a `Uint8Array`.

  Elixir strings are binaries too, so a plain binary is written as a string when it is
  valid UTF-8, and as a buffer only when it is not. Wrap the data in `Yex.Buffer` to
  always write it as a buffer. Buffers are always read back as `Yex.Buffer`, so a value
  that is read and written again keeps its type.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "bytes", Yex.Buffer.new(<<1, 2, 3>>))
      iex> Yex.Map.fetch(map, "bytes")
      {:ok, %Yex.Buffer{data: <<1, 2, 3>>}}
      iex> Yex.Map.set(map, "invalid_utf8", <<255>>)
      iex> Yex.Map.fetch(map, "invalid_utf8")
      {:ok, %Yex.Buffer{data: <<255>>}}
      iex> Yex.Map.set(map, "string", <<1, 2, 3>>)
      iex> Yex.Map.fetch(map, "string")
      {:ok, <<1, 2, 3>>}
  """

  @enforce_keys [:data]
  defstruct [:data]

  @type t :: %__MODULE__{data: binary()}

  @doc """
  Wraps `data` so that it is written as a buffer.
  """
  @spec new(binary()) :: t()
  def new(data) when is_binary(data), do: %__MODULE__{data: data}
end
