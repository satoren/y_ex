defmodule Yex.Array do
  @moduledoc """
  A shareable Array-like type that supports efficient insert/delete of elements at any position.
  """
  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  @doc """
  Insert content at the specified index.
  """
  def insert(%__MODULE__{} = array, index, content) do
    Yex.Nif.array_insert(array, index, content)
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
    Yex.Nif.array_delete_range(array, index, length) |> Yex.Nif.Util.unwrap_ok_tuple()
  end

  @doc """
  Get content at the specified index.
  """
  @spec get(t, integer()) :: {:ok, term()} | :error
  def get(%__MODULE__{} = array, index) do
    index = if index < 0, do: __MODULE__.length(array) + index, else: index
    Yex.Nif.array_get(array, index) |> Yex.Nif.Util.unwrap_tuple()
  end

  @doc """
  Returns as list

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.push(array, Yex.ArrayPrelim.from([1, 2]))
      iex> ["Hello", "World", %Yex.Array{}] = Yex.Array.to_list(array)

  """
  def to_list(%__MODULE__{} = array) do
    Yex.Nif.array_to_list(array)
  end

  @doc """
  Returns the length of the array

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.length(array)
      2
  """
  def length(%__MODULE__{} = array) do
    Yex.Nif.array_length(array)
  end

  @doc """
  Convert to json-compatible format.

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> array = Yex.Doc.get_array(doc, "array")
      iex> Yex.Array.push(array, "Hello")
      iex> Yex.Array.push(array, "World")
      iex> Yex.Array.to_json(array)
      ["Hello", "World"]
  """
  @spec to_json(t) :: term()
  def to_json(%__MODULE__{} = array) do
    Yex.Nif.array_to_json(array)
  end
end

defmodule Yex.ArrayPrelim do
  @moduledoc """
  A preliminary array. It can be used to early initialize the contents of a Array.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.ArrayPrelim.from(["Hello", "World"]))
      iex> {:ok, %Yex.Array{} = array} = Yex.Map.get(map, "key")
      iex> Yex.Array.get(array, 1)
      {:ok, "World"}

  """
  defstruct [
    :list
  ]

  @type t :: %__MODULE__{
          list: list()
        }

  def from(enumerable) do
    %__MODULE__{list: Enum.to_list(enumerable)}
  end
end