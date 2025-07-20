defmodule Yex.Map do
  @moduledoc """
  A shareable Map type that supports concurrent modifications with automatic conflict resolution.
  This module provides functionality for collaborative key-value pair management with support for
  nested shared types and JSON compatibility.

  ## Features
  - Concurrent modifications with automatic conflict resolution
  - Support for nested shared types (Array, Text, Map)
  - JSON-compatible serialization
  - Key-value pair management with atomic operations
  - Observable changes for real-time collaboration
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
  Sets a key-value pair in the map.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `map` - The map to modify
    * `key` - The key to set
    * `content` - The value to associate with the key

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
  Deletes a key from the map.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `map` - The map to modify
    * `key` - The key to delete

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
  Retrieves a value by key from the map.
  Returns {:ok, value} if found, :error if not found.

  ## Parameters
    * `map` - The map to query
    * `key` - The key to look up

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

  @doc """
  Similar to fetch/2 but raises ArgumentError if the key is not found.

  ## Parameters
    * `map` - The map to query
    * `key` - The key to look up

  ## Raises
    * ArgumentError - If the key is not found
  """
  @spec fetch!(t, binary()) :: term()
  def fetch!(%__MODULE__{} = map, key) do
    case fetch(map, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Key not found"
    end
  end

  @doc """
  Checks if a key exists in the map.
  Returns true if the key exists, false otherwise.

  ## Parameters
    * `map` - The map to check
    * `key` - The key to look for
  """
  @spec has_key?(t, binary()) :: boolean()
  def has_key?(%__MODULE__{doc: doc} = map, key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_contains_key(map, cur_txn(map), key)
    )
  end

  @doc """
  Converts the map to a standard Elixir map.
  This is useful when you need to work with the map's contents in a non-collaborative context.

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

  @doc """
  Converts the map to a list of key-value tuples.
  """
  @spec to_list(t) :: list()
  def to_list(map) do
    to_map(map) |> Enum.to_list()
  end

  @doc """
  Returns the number of key-value pairs in the map.
  """
  @spec size(t) :: integer()
  def size(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_size(map, cur_txn(map))
    )
  end

  @doc """
  Converts the map to a JSON-compatible format.
  This is useful for serialization or when you need to transfer the map's contents.

  ## Examples
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

  @doc false
  # Gets the current transaction reference from the process dictionary for the given document
  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @doc """
  Converts the map to its preliminary representation.
  This is useful when you need to serialize or transfer the map's contents.

  ## Parameters
    * `map` - The map to convert
  """
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
      value = Yex.normalize(value)

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
  A preliminary map representation used for initializing map content.
  This module provides functionality for creating map content before it is
  inserted into a shared document.

  ## Use Cases
  - Creating map content before inserting into a document
  - Serializing map content for transfer between documents
  - Initializing map content with specific key-value pairs
  - Preparing nested data structures for shared documents

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
          map: %{binary() => Yex.input_type()}
        }

  @doc """
  Creates a new MapPrelim from an Elixir map.
  This is useful when you want to initialize a shared map with predefined content.

  ## Parameters
    * `map` - An Elixir map to convert to a preliminary map

  ## Examples
      iex> prelim = Yex.MapPrelim.from(%{"key" => "value", "nested" => %{"inner" => "data"}})
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "content", prelim)
  """
  @spec from(%{binary() => Yex.input_type()}) :: t()
  def from(%{} = map) do
    %__MODULE__{map: map}
  end
end
