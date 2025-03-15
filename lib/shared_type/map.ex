defmodule Yex.Map do
  @moduledoc """
  A shareable Map type.
  """
  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  alias Yex.Doc
  require Yex.Doc

  @doc """
  set a key-value pair in the map.
  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      :ok
  """
  @spec set(t, term(), term()) :: term()
  def set(%__MODULE__{doc: doc} = map, key, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_set(map, cur_txn(map), key, content)
    )
  end

  @doc """
  delete a key from the map.
  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> Yex.Map.delete(map, "plane")
      :ok
  """
  @spec delete(t, term()) :: :ok
  def delete(%__MODULE__{doc: doc} = map, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_delete(map, cur_txn(map), key)
    )
  end

  @doc """
  get a key from the map.
    ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> Yex.Map.get(map, "plane")
      {:ok, ["Hello", "World"]}
      iex> Yex.Map.get(map, "not_found")
      :error
  """
  @deprecated "Rename to `fetch/2`"
  @spec get(t, binary()) :: {:ok, term()} | :error
  def get(%__MODULE__{} = map, key) do
    fetch(map, key)
  end

  @doc """
  get a key from the map.
  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> Yex.Map.fetch(map, "plane")
      {:ok, ["Hello", "World"]}
      iex> Yex.Map.fetch(map, "not_found")
      :error
  """
  @spec fetch(t, binary()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{doc: doc} = map, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_get(map, cur_txn(map), key)
    )
  end

  @spec fetch(t, binary()) :: {:ok, term()} | :error
  def fetch!(%__MODULE__{} = map, key) do
    case fetch(map, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Key not found"
    end
  end

  @spec has_key?(t, binary()) :: boolean()
  def has_key?(%__MODULE__{doc: doc} = map, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_contains_key(map, cur_txn(map), key)
    )
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
  @spec to_map(t) :: map()
  def to_map(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_to_map(map, cur_txn(map))
    )
  end

  def to_list(map) do
    to_map(map) |> Enum.to_list()
  end

  @spec size(t) :: integer()
  def size(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_size(map, cur_txn(map))
    )
  end

  @doc """
  Convert to json-compatible format.

  ## Examples shows a map being created incrementally then returned
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "array", Yex.ArrayPrelim.from(["Hello", "World"]))
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> assert %{"plane" => ["Hello", "World"], "array" => ["Hello", "World"]} = Yex.Map.to_json(map)
  """
  @spec to_json(t) :: map()
  def to_json(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_to_json(map, cur_txn(map))
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @spec as_prelim(t) :: Yex.MapPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do:
        Yex.Map.to_list(map)
        |> Enum.map(fn {key, value} -> {key, Yex.Output.as_prelim(value)} end)
        |> Map.new()
        |> Yex.MapPrelim.from()
    )
  end

  defimpl Yex.Output do
    def as_prelim(map) do
      Yex.Map.as_prelim(map)
    end
  end

  defimpl Enumerable do
    def count(map) do
      {:ok, Yex.Map.size(map)}
    end

    def member?(map, {key, value}) do
      case Yex.Map.fetch(map, key) do
        {:ok, ^value} -> {:ok, true}
        _ -> {:ok, false}
      end
    end

    def member?(_, _) do
      {:ok, false}
    end

    def slice(map) do
      list = Yex.Map.to_list(map)
      size = Enum.count(list)
      {:ok, size, &Enum.slice(list, &1, &2)}
    end

    def reduce(map, acc, fun) do
      Enumerable.List.reduce(Yex.Map.to_list(map), acc, fun)
    end
  end
end

defmodule Yex.MapPrelim do
  @moduledoc """
  A preliminary map. It can be used to early initialize the contents of a Map.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert(array, 0, Yex.MapPrelim.from(%{ "key" => "value" }))
      iex> {:ok, %Yex.Map{} = map} = Yex.Array.fetch(array, 0)
      iex> Yex.Map.fetch(map, "key")
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
