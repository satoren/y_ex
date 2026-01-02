defmodule Yex.Array do
  @moduledoc """
  A shareable Array-like type that supports efficient insert/delete of elements at any position.
  This module provides functionality for collaborative array manipulation with support for
  concurrent modifications and automatic conflict resolution.

  ## Features
  - Insert and delete elements at any position
  - Push and unshift operations for adding elements
  - Move elements between positions
  - Support for nested shared types
  - Automatic conflict resolution for concurrent modifications
  """
  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @type value :: term()
  alias Yex.Doc
  require Yex.Doc

  @u32_max 2 ** 32 - 1

  @doc """
  Inserts content at the specified index.
  Returns :ok on success.

  ## Parameters
    * `array` - The array to modify
    * `index` - The position to insert at (0-based). Supports negative indexing: -1 for end (append), -2 for before last, etc.
    * `content` - The content to insert (can be any JSON-compatible value or shared type)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert(array, 0, "Hello")
      :ok
      iex> Yex.Array.insert(array, 1, "World")
      :ok
      iex> Yex.Array.to_json(array)
      ["Hello", "World"]

      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert(array, 0, Yex.ArrayPrelim.from([1, 2, 3]))
      :ok
      iex> {:ok, nested} = Yex.Array.fetch(array, 0)
      iex> Yex.Array.to_json(nested)
      [1.0, 2.0, 3.0]

      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "first")
      iex> Yex.Array.push(array, "second")
      iex> Yex.Array.push(array, "third")
      iex> Yex.Array.insert(array, -1, "after_last")
      :ok
      iex> Yex.Array.to_json(array)
      ["first", "second", "third", "after_last"]
  """
  @spec insert(t, integer(), Yex.input_type()) :: :ok
  def insert(%__MODULE__{doc: doc} = array, index, content) when is_integer(index) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_insert(array, cur_txn(array), index, content)
    end
  end

  @doc """
  Inserts content at the specified index and returns the inserted content.
  Returns the content on success, raises on failure.

  ## Parameters
    * `array` - The array to modify
    * `index` - The position to insert at (0-based)
    * `content` - The content to insert
  """
  @spec insert_and_get(t, integer(), Yex.input_type()) :: value()
  def insert_and_get(%__MODULE__{doc: doc} = array, index, content) when is_integer(index) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_insert_and_get(array, cur_txn(array), index, content)
    end
  end

  @doc """
  Insert contents at the specified index.

  ## Parameters
    * `array` - The array to modify
    * `index` - The position to insert at (0-based). Supports negative indexing: -1 for end (append), -2 for before last, etc.
    * `contents` - A list of contents to insert

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert_list(array, 0, [1,2,3,4,5])
      iex> Yex.Array.to_json(array)
      [1.0, 2.0, 3.0, 4.0, 5.0]
  """
  @spec insert_list(t, integer(), list(Yex.any_type())) :: :ok
  def insert_list(%__MODULE__{doc: doc} = array, index, contents) when is_integer(index) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_insert_list(array, cur_txn(array), index, contents)
    end
  end

  @doc """
  Pushes content to the end of the array.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `array` - The array to modify
    * `content` - The content to append
  """
  @spec push(t, Yex.input_type()) :: :ok
  def push(array, content) do
    insert(array, @u32_max, content)
  end

  @doc """
  Pushes content to the end of the array and returns the pushed content.
  Returns the content on success, raises on failure.

  ## Parameters
    * `array` - The array to modify
    * `content` - The content to append

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> value = Yex.Array.push_and_get(array, "Hello")
      iex> value
      "Hello"
  """
  @spec push_and_get(t, Yex.input_type()) :: value()
  def push_and_get(array, content) do
    insert_and_get(array, @u32_max, content)
  end

  @doc """
  Unshifts content to the beginning of the array.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `array` - The array to modify
    * `content` - The content to prepend
  """
  def unshift(%__MODULE__{} = array, content) do
    insert(array, 0, content)
  end

  @doc """
  Deletes content at the specified index.
  Returns :ok on success, :error on failure.

  ## Parameters
    * `array` - The array to modify
    * `index` - The position to delete from (0-based)
  """
  @spec delete(t, integer()) :: :ok
  def delete(%__MODULE__{} = array, index) do
    delete_range(array, index, 1)
  end

  @doc """
  Deletes a range of contents starting at the specified index.
  Returns :ok on success, :error on failure.
  capped to the array bounds.

  ## Parameters
    * `array` - The array to modify
    * `index` - The starting position to delete from (0-based)
    * `length` - The number of elements to delete
  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "1")
      iex> Yex.Array.push(array, "2")
      iex> Yex.Array.push(array, "3")
      iex> :ok = Yex.Array.delete_range(array, 0, 2); Yex.Array.to_list(array)
      ["3"]
      iex> :ok = Yex.Array.delete_range(array, 0, 1); Yex.Array.to_list(array)
      []
      iex> Yex.Array.insert_list(array, 0, ["1", "2", "3", "4", "5"])
      iex> Yex.Array.delete_range(array, -4, 10); Yex.Array.to_list(array)
      ["1"]

  """
  @spec delete_range(t, integer(), integer()) :: :ok
  def delete_range(%__MODULE__{doc: doc} = array, index, length)
      when is_integer(index) and is_integer(length) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_delete_range(array, cur_txn(array), index, length)
    end
  end

  @doc """
  Moves element found at `source` index into `target` index position. Both indexes refer to a current state of the document.
  ## Examples pushes a string then fetches it back
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, Yex.ArrayPrelim.from([1, 2]))
      iex> Yex.Array.push(array, Yex.ArrayPrelim.from([3, 4]))
      iex> :ok = Yex.Array.move_to(array, 0, 2)
      iex> Yex.Array.to_json(array)
      [[3.0, 4.0], [1.0, 2.0]]
  """
  @spec move_to(t, integer(), integer()) :: :ok
  def move_to(%__MODULE__{doc: doc} = array, from, to) when is_integer(from) and is_integer(to) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_move_to(array, cur_txn(array), from, to)
    end
  end

  @doc """
  ### ⚠️ Experimental
  Quotes a range of array content, returning it as a new WeakPrelim object.
  """
  @spec quote(Yex.Array.t(), integer(), integer()) :: Yex.WeakPrelim.t() | {:error, term()}
  def quote(%__MODULE__{doc: doc} = array, index, length)
      when is_integer(index) and is_integer(length) and length > 0 do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_quote(array, cur_txn(array), index, length)
    end
  end

  def quote(_array, _index, _length) do
    {:error, :out_of_bounds}
  end

  @spec get(t, integer(), default :: value()) :: value()
  def get(array, index, default \\ nil) do
    case fetch(array, index) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Gets a value by index from the array, or lazily evaluates the given function if the index is out of bounds.
  This is useful when the default value is expensive to compute and should only be evaluated when needed.

  ## Parameters
    * `array` - The array to query
    * `index` - The index to look up
    * `fun` - A function that returns the default value (only called if index is out of bounds)

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.get_lazy(array, 0, fn -> "Default" end)
      "Hello"
      iex> Yex.Array.get_lazy(array, 10, fn -> "Computed" end)
      "Computed"

  Particularly useful with `insert_and_get/3` or `push_and_get/2` for get-or-create patterns:

      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> # Get existing value or create and return new one
      iex> value = Yex.Array.get_lazy(array, 0, fn ->
      ...>   Yex.Array.push_and_get(array, "initial")
      ...> end)
      iex> value
      "initial"
      iex> # Next call returns existing value without calling the function
      iex> Yex.Array.get_lazy(array, 0, fn -> Yex.Array.push_and_get(array, "initial") end)
      "initial"
  """
  @spec get_lazy(t, integer(), fun :: (-> value())) :: value()
  def get_lazy(%__MODULE__{} = array, index, fun) do
    case fetch(array, index) do
      {:ok, value} -> value
      :error -> fun.()
    end
  end

  @doc """
  Get content at the specified index.
  ## Examples pushes a string then fetches it back
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.fetch(array, 0)
      {:ok, "Hello"}
  """
  @spec fetch(t, integer()) :: {:ok, value()} | :error
  def fetch(%__MODULE__{doc: doc} = array, index) when is_integer(index) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_get(array, cur_txn(array), index)
    end
  end

  @doc """
  Get content at the specified index or raises ArgumentError if out of bounds.
  @see fetch/2
  """
  @spec fetch!(t, integer()) :: value()
  def fetch!(%__MODULE__{} = array, index) when is_integer(index) do
    case fetch(array, index) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Index out of bounds"
    end
  end

  @doc """
  Returns as list

  ## Examples adds a few items to an array, then gets them back as Elixir List
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.push(array, Yex.ArrayPrelim.from([1, 2]))
      iex> ["Hello", "World", %Yex.Array{}] = Yex.Array.to_list(array)

  """
  def to_list(%__MODULE__{doc: doc} = array) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_to_list(array, cur_txn(array))
    end
  end

  @doc """
   slices the array from start_index for amount of elements, then gets them back as Elixir List.
  """
  def slice(array, start_index, amount) do
    slice_take_every(array, start_index, amount, 1)
  end

  @doc """
    slices the array from start_index for amount of elements, then gets them back as Elixir List and takes every `step` element.
  """
  def slice_take_every(_array, _start_index, _amount, 0) do
    []
  end

  def slice_take_every(%__MODULE__{doc: doc} = array, start_index, amount, step)
      when is_integer(step) and step > 0 do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_slice(array, cur_txn(array), start_index, amount, step)
    end
  end

  @doc """
  Returns the length of the array

  ## Examples adds a few items to an array and returns its length
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.length(array)
      2
  """
  def length(%__MODULE__{doc: doc} = array) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_length(array, cur_txn(array))
    end
  end

  @doc """
  Convert to json-compatible format.

  ## Examples adds a few items to an array and returns as Elixir List
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.to_json(array)
      ["Hello", "World"]
  """
  @spec to_json(t) :: term()
  def to_json(%__MODULE__{doc: doc} = array) do
    Doc.run_in_worker_process doc do
      Yex.Nif.array_to_json(array, cur_txn(array))
    end
  end

  def member?(array, val) do
    val = Yex.normalize(val)
    Enum.member?(to_list(array), val)
  end

  @spec observe(
          Yex.Array.t(),
          handler :: (update :: Yex.ArrayEvent.t(), origin :: term() -> nil)
        ) :: reference()
  def observe(%__MODULE__{doc: doc} = array, handler) do
    Yex.SharedType.observe(array,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
    )
  end

  @spec observe_deep(
          Yex.Array.t(),
          handler :: (update :: list(Yex.event_type()), origin :: term() -> nil)
        ) :: reference()
  def observe_deep(%__MODULE__{doc: doc} = array, handler) do
    Yex.SharedType.observe_deep(array,
      metadata: {Yex.ObserveCallbackHandler, handler},
      notify_pid: doc.worker_pid
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @doc """
  Converts the array to its preliminary representation.
  This is useful when you need to serialize or transfer the array's contents.

  ## Parameters
    * `array` - The array to convert
  """
  @spec as_prelim(t) :: Yex.ArrayPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = array) do
    Doc.run_in_worker_process(doc,
      do:
        Yex.Array.to_list(array)
        |> Enum.map(&Yex.Output.as_prelim/1)
        |> Yex.ArrayPrelim.from()
    )
  end

  defimpl Yex.Output do
    def as_prelim(array) do
      Yex.Array.as_prelim(array)
    end
  end

  defimpl Enumerable do
    def count(array) do
      {:ok, Yex.Array.length(array)}
    end

    def member?(array, val) do
      {:ok, Yex.Array.member?(array, val)}
    end

    def slice(array) do
      size = Yex.Array.length(array)
      {:ok, size, &slice_impl(array, &1, &2, &3)}
    end

    defp slice_impl(array, start, length, step) do
      # Optimize for single element access (Enum.at)
      if length == 1 and step == 1 do
        case Yex.Array.fetch(array, start) do
          {:ok, value} -> [value]
          :error -> []
        end
      else
        Yex.Array.slice_take_every(array, start, length, step)
      end
    end

    def reduce(array, acc, fun) do
      Enumerable.List.reduce(Yex.Array.to_list(array), acc, fun)
    end
  end
end

defmodule Yex.ArrayPrelim do
  @moduledoc """
  A preliminary array. It can be used to early initialize the contents of a Array.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.ArrayPrelim.from(["Hello", "World"]))
      iex> {:ok, %Yex.Array{} = array} = Yex.Map.fetch(map, "key")
      iex> Yex.Array.fetch(array, 1)
      {:ok, "World"}

  """
  defstruct [
    :list
  ]

  @type t :: %__MODULE__{
          list: list(Yex.input_type())
        }

  @spec from(Enumerable.t(Yex.input_type())) :: t
  def from(enumerable) do
    %__MODULE__{list: Enum.to_list(enumerable)}
  end
end
