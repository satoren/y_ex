defmodule Yex.Array do
  @moduledoc """
  A shareable Array-like type that supports efficient insert/delete of elements at any position.
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
  Insert content at the specified index.
  """
  def insert(%__MODULE__{} = array, index, content) do
    Yex.Nif.array_insert(array, cur_txn(array), index, content)
  end

  @doc """
  Insert contents at the specified index.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.insert_list(array, 0, [1,2,3,4,5])
      iex> Yex.Array.to_json(array)
      [1, 2, 3, 4, 5]
  """
  @spec insert_list(t, integer(), list()) :: :ok
  def insert_list(%__MODULE__{} = array, index, contents) do
    Yex.Nif.array_insert_list(array, cur_txn(array), index, contents)
  end

  @doc """
  Push content to the end of the array.
  """
  def push(%__MODULE__{} = array, content) do
    insert(array, __MODULE__.length(array), content)
  end

  @doc """
  Unshift content to the beginning of the array.
  """
  def unshift(%__MODULE__{} = array, content) do
    insert(array, 0, content)
  end

  @doc """
  Delete content at the specified index.
  """
  @spec delete(t, integer()) :: :ok
  def delete(%__MODULE__{} = array, index) do
    delete_range(array, index, 1)
  end

  @doc """
  Delete contents in the specified range.
  """
  @spec delete_range(t, integer(), integer()) :: :ok
  def delete_range(%__MODULE__{} = array, index, length) do
    index = if index < 0, do: __MODULE__.length(array) + index, else: index

    Yex.Nif.array_delete_range(array, cur_txn(array), index, length)
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
      [[3, 4], [1, 2]]
  """
  @spec move_to(t, integer(), integer()) :: :ok
  def move_to(%__MODULE__{} = array, from, to) do
    Yex.Nif.array_move_to(array, cur_txn(array), from, to)
  end

  @deprecated "Rename to `fetch/2`"
  @spec get(t, integer()) :: {:ok, term()} | :error
  def get(array, index) do
    fetch(array, index)
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
  @spec fetch(t, integer()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = array, index) do
    index = if index < 0, do: __MODULE__.length(array) + index, else: index
    Yex.Nif.array_get(array, cur_txn(array), index)
  end

  @spec fetch!(t, integer()) :: term()
  def fetch!(%__MODULE__{} = array, index) do
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
  def to_list(%__MODULE__{} = array) do
    Yex.Nif.array_to_list(array, cur_txn(array))
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
  def length(%__MODULE__{} = array) do
    Yex.Nif.array_length(array, cur_txn(array))
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
  def to_json(%__MODULE__{} = array) do
    Yex.Nif.array_to_json(array, cur_txn(array))
  end

  defdelegate observe(t), to: Yex.SharedType
  defdelegate observe(t, option), to: Yex.SharedType
  defdelegate observe_deep(t), to: Yex.SharedType
  defdelegate observe_deep(t, option), to: Yex.SharedType

  defp cur_txn(%__MODULE__{doc: doc_ref}) do
    Process.get(doc_ref, nil)
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
          list: list()
        }

  @spec from(Enumerable.t()) :: t
  def from(enumerable) do
    %__MODULE__{list: Enum.to_list(enumerable)}
  end
end
