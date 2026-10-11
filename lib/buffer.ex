defmodule Yex.Buffer do
  @moduledoc """
  Bytes stored as a buffer value: a `Uint8Array` to a Yjs client.

  Elixir has one type for text and bytes, so a bare binary is stored as a
  string when it is valid UTF-8 and as a buffer only when it is not. Wrap the
  bytes in a `Yex.Buffer` to store them as a buffer whatever they contain, in
  a map, an array, a text's formatting attributes, an XML attribute or a prelim.

  A buffer is always read back as a `Yex.Buffer`, so a value that is read and
  written again keeps its type.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "image", Yex.Buffer.from("RIFF"))
      iex> Yex.Map.fetch(map, "image")
      {:ok, %Yex.Buffer{data: "RIFF"}}
      iex> Yex.Map.set(map, "bytes", <<0xFF, 0xD8>>)
      iex> Yex.Map.fetch(map, "bytes")
      {:ok, %Yex.Buffer{data: <<0xFF, 0xD8>>}}
      iex> Yex.Map.set(map, "text", "RIFF")
      iex> Yex.Map.fetch(map, "text")
      {:ok, "RIFF"}
  """

  @enforce_keys [:data]
  defstruct [:data]

  @type t :: %__MODULE__{data: binary()}

  @doc """
  Wraps `data`, the bytes to store as a buffer.

  ## Examples
      iex> Yex.Buffer.from(<<0xFF, 0xD8>>)
      %Yex.Buffer{data: <<0xFF, 0xD8>>}
  """
  @spec from(binary()) :: t()
  def from(data) when is_binary(data), do: %__MODULE__{data: data}
end
