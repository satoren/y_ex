defmodule Yex.ArrayEvent do
  @moduledoc """
  Event when Array type changes

  @see Yex.Array.observe/1
  @see Yex.Array.observe_deep/1
  @see Yex.Map.observe_deep/1
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

  Event when Map type changes

  @see Yex.Map.observe/1
  @see Yex.Array.observe_deep/1
  @see Yex.Map.observe_deep/1
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
