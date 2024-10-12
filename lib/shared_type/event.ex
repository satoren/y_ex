defmodule Yex.ArrayEvent do
  @moduledoc """

  """
  defstruct [
    :path,
    :target
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Array.t()
        }
end

defmodule Yex.MapEvent do
  @moduledoc """

  """
  defstruct [
    :path,
    :target
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Map.t()
        }
end
