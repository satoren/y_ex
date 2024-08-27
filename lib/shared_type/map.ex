defmodule Yex.Map do
  @moduledoc """
  A shareable Map type.
  """
  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: reference(),
          reference: reference()
        }

  @doc """
  set a key-value pair in the map.
  """
  def set(%__MODULE__{} = map, key, content) do
    Yex.Nif.map_set(map, cur_txn(map), key, content)
  end

  @doc """
  delete a key from the map.
  """
  def delete(%__MODULE__{} = map, key) do
    Yex.Nif.map_delete(map, cur_txn(map), key)
  end

  @doc """
  get a key from the map.
  """
  def get(%__MODULE__{} = map, key) do
    Yex.Nif.map_get(map, cur_txn(map), key) |> Yex.Nif.Util.unwrap_tuple()
  end

  @doc """
  Convert to elixir map.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "array", Yex.ArrayPrelim.from(["Hello", "World"]))
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> assert %{"plane" => ["Hello", "World"], "array" => %Yex.Array{}} = Yex.Map.to_map(map)
  """
  def to_map(%__MODULE__{} = map) do
    Yex.Nif.map_to_map(map, cur_txn(map))
  end

  def size(%__MODULE__{} = map) do
    Yex.Nif.map_size(map, cur_txn(map))
  end

  @doc """
  Convert to json-compatible format.

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "array", Yex.ArrayPrelim.from(["Hello", "World"]))
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> assert %{"plane" => ["Hello", "World"], "array" => ["Hello", "World"]} = Yex.Map.to_json(map)
  """
  def to_json(%__MODULE__{} = map) do
    Yex.Nif.map_to_json(map, cur_txn(map))
  end

  defp cur_txn(%__MODULE__{doc: doc_ref}) do
    Process.get(doc_ref, nil)
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

  @type t :: %__MODULE__{
          map: map()
        }

  def from(%{} = map) do
    %__MODULE__{map: map}
  end
end
