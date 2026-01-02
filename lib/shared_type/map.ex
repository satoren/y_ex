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

  @type value :: term()

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
  @spec set(t, binary(), Yex.input_type()) :: :ok
  def set(%__MODULE__{doc: doc} = map, key, content) when is_binary(key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_set(map, cur_txn(map), key, content)
    )
  end

  @doc """
  Sets a key-value pair in the map and returns the set value.
  Returns the value on success, raises on failure.

  ## Parameters
    * `map` - The map to modify
    * `key` - The key to set
    * `content` - The value to associate with the key

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> value = Yex.Map.set_and_get(map, "plane", ["Hello", "World"])
      iex> value
      ["Hello", "World"]
  """
  @spec set_and_get(t, binary(), Yex.input_type()) :: value()
  def set_and_get(%__MODULE__{doc: doc} = map, key, content) when is_binary(key) do
    Doc.run_in_worker_process doc do
      :ok = Yex.Nif.map_set(map, cur_txn(map), key, content)

      case Yex.Nif.map_get(map, cur_txn(map), key) do
        {:ok, value} -> value
        :error -> raise RuntimeError, "Failed to get inserted value"
      end
    end
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
  @spec delete(t, binary()) :: :ok
  def delete(%__MODULE__{doc: doc} = map, key) when is_binary(key) do
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
      ["Hello", "World"]
      iex> Yex.Map.get(map, "not_found")
      nil
  """
  @spec get(t, binary(), default :: value()) :: value()
  def get(%__MODULE__{} = map, key, default \\ nil) do
    case fetch(map, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Gets a value by key from the map, or lazily evaluates the given function if the key is not found.
  This is useful when the default value is expensive to compute and should only be evaluated when needed.

  ## Parameters
    * `map` - The map to query
    * `key` - The key to look up
    * `fun` - A function that returns the default value (only called if key is not found)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> Yex.Map.get_lazy(map, "plane", fn -> ["Default"] end)
      ["Hello", "World"]
      iex> Yex.Map.get_lazy(map, "not_found", fn -> ["Computed"] end)
      ["Computed"]

  Particularly useful with `set_and_get/3` for get-or-create patterns:

      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> # Get existing value or create and return new one
      iex> value = Yex.Map.get_lazy(map, "counter", fn ->
      ...>   Yex.Map.set_and_get(map, "counter", 0)
      ...> end)
      iex> value
      0.0
      iex> # Next call returns existing value without calling the function
      iex> Yex.Map.get_lazy(map, "counter", fn -> Yex.Map.set_and_get(map, "counter", 0) end)
      0.0
  """
  @spec get_lazy(t, binary(), fun :: (-> value())) :: value()
  def get_lazy(%__MODULE__{} = map, key, fun) do
    case fetch(map, key) do
      {:ok, value} -> value
      :error -> fun.()
    end
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
  @spec fetch(t, binary()) :: {:ok, value()} | :error
  def fetch(%__MODULE__{doc: doc} = map, key) when is_binary(key) do
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
  @spec fetch!(t, binary()) :: value()
  def fetch!(%__MODULE__{} = map, key) when is_binary(key) do
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
  def has_key?(%__MODULE__{doc: doc} = map, key) when is_binary(key) do
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
  Returns a list of all keys in the map.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "foo", "bar")
      iex> Yex.Map.set(map, "baz", "qux")
      iex> keys = Yex.Map.keys(map)
      iex> Enum.sort(keys) # keys order is not guaranteed
      ["baz", "foo"]
  """
  @spec keys(t) :: list(binary())
  def keys(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_keys(map, cur_txn(map))
    )
  end

  @doc """
  Returns a list of all values in the map.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "foo", "bar")
      iex> Yex.Map.set(map, "baz", 123)
      iex> values = Yex.Map.values(map)
      iex> Enum.sort(values) # values order is not guaranteed
      [123.0, "bar"]
  """
  @spec values(t) :: list(value())
  def values(%__MODULE__{doc: doc} = map) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_values(map, cur_txn(map))
    )
  end

  @doc """
  Converts the map to a list of key-value tuples.
  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "plane", ["Hello", "World"])
      iex> Yex.Map.to_list(map)
      [{"plane", ["Hello", "World"]}]
  """
  @spec to_list(t) :: list({binary(), term()})
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

  @doc """
  ### ⚠️ Experimental
  Creates a weak link to a value in the map by key.
  Returns [Yex.WeakPrelim] to a given `key`, if it exists in a current map.
  """
  @spec link(t, binary()) :: Yex.WeakPrelim.t() | nil
  def link(%__MODULE__{doc: doc} = map, key) when is_binary(key) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.map_link(map, cur_txn(map), key)
    )
  end

  @spec observe(
          t,
          handler :: (update :: Yex.MapEvent.t(), origin :: term() -> nil)
        ) :: reference()
  def observe(%__MODULE__{doc: doc} = map, handler) do
    Yex.SharedType.observe(map,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
    )
  end

  @spec observe_deep(
          t,
          handler :: (update :: list(Yex.event_type()), origin :: term() -> nil)
        ) :: reference()
  def observe_deep(%__MODULE__{doc: doc} = map, handler) do
    Yex.SharedType.observe_deep(map,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
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
      {:ok, size, &slice_impl(list, &1, &2, &3)}
    end

    defp slice_impl(list, start, length, step) do
      list
      |> Enum.slice(start, length)
      |> Enum.take_every(step)
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
  @spec from(%{binary() => Yex.input_type()} | [{binary(), Yex.input_type()}]) :: t()
  def from(%{} = map) do
    %__MODULE__{map: map}
  end

  def from(entries) when is_list(entries) do
    %__MODULE__{map: Map.new(entries)}
  end
end
