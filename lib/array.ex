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

  def insert(%__MODULE__{} = array, index, content) do
    Yex.Nif.array_insert(array, index, content)
  end

  def push(%__MODULE__{} = array, content) do
    insert(array, __MODULE__.length(array), content)
  end

  def unshift(%__MODULE__{} = array, content) do
    insert(array, 0, content)
  end

  def delete(%__MODULE__{} = array, index) do
    delete_range(array, index, 1)
  end

  def delete_range(%__MODULE__{} = array, index, length) do
    Yex.Nif.array_delete_range(array, index, length)
  end

  def get(%__MODULE__{} = array, index) do
    Yex.Nif.array_get(array, index)
  end

  def to_list(%__MODULE__{} = array) do
    Yex.Nif.array_to_list(array)
  end

  def length(%__MODULE__{} = array) do
    Yex.Nif.array_length(array)
  end

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

  def from(enumerable) do
    %__MODULE__{list: Enum.to_list(enumerable)}
  end
end
