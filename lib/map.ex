defmodule Yex.Map do
  @moduledoc """
  A shareable Map type.
  """
  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  def set(%__MODULE__{} = map, key, content) do
    Yex.Nif.map_set(map, key, content)
  end

  def delete(%__MODULE__{} = map, key) do
    Yex.Nif.map_delete(map, key)
  end

  def get(%__MODULE__{} = map, key) do
    Yex.Nif.map_get(map, key)
  end

  def to_map(%__MODULE__{} = map) do
    Yex.Nif.map_to_map(map)
  end

  def size(%__MODULE__{} = map) do
    Yex.Nif.map_size(map)
  end

  @doc """
  Convert to json-compatible format.

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", ["Hello", "World"])
      iex> Yex.Map.to_json(map)
      %{"key" => ["Hello", "World"]}
  """
  def to_json(%__MODULE__{} = map) do
    Yex.Nif.map_to_json(map)
  end
end

defmodule Yex.MapPrelim do
  @moduledoc """
  A preliminary map. It can be used to early initialize the contents of a Map.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert(array, 0, Yex.MapPrelim.from(%{ "key" => "value" }))
      iex> {:ok, %Yex.Map{} = map} = Yex.Array.get(array, 0)
      iex> Yex.Map.get(map, "key")
      {:ok, "value"}
  """
  defstruct [
    :map
  ]

  def from(%{} = map) do
    %__MODULE__{map: map}
  end
end
