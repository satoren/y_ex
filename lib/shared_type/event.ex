defmodule Yex.ArrayEvent do
  @moduledoc """
  Event when Array type changes

  @see Yex.Array.observe/1
  @see Yex.Array.observe_deep/1
  @see Yex.Map.observe_deep/1
  """
  defstruct [
    :path,
    :target,
    :change
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Array.t(),
          change: %{insert: list()} | %{delete: number()} | %{}
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
    :target,
    :keys
  ]

  @type change ::
          %{action: :add, new_value: term()}
          | %{action: :delete, old_value: term()}
          | %{action: :update, old_value: term(), new_value: term()}
  @type keys :: %{String.t() => %{}}

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Map.t(),
          keys: keys
        }
end

defmodule Yex.TextEvent do
  @moduledoc """

  Event when Text type changes

  @see Yex.Text.observe/1
  @see Yex.Array.observe_deep/1
  @see Yex.Map.observe_deep/1
  """
  defstruct [
    :path,
    :target,
    :delta
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Map.t(),
          delta: Yex.Text.delta()
        }
end
