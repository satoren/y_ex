defmodule Yex.Map do
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

  def to_json(%__MODULE__{} = map) do
    Yex.Nif.map_to_json(map)
  end
end

defmodule Yex.MapPrelim do
  defstruct [
    :map
  ]

  def from(%{} = map) do
    %__MODULE__{map: map}
  end
end
