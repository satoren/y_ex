defmodule Yex.ArrayEvent do
  @moduledoc """
  Event when Array type changes

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
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

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
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

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
  """
  defstruct [
    :path,
    :target,
    :delta
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Text.t(),
          delta: Yex.Text.delta()
        }
end

defmodule Yex.XmlEvent do
  @moduledoc """

  Event when XMLFragment/Element type changes

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
  """
  defstruct [
    :path,
    :target,
    :delta,
    :keys
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.Map.t(),
          delta: Yex.Text.delta(),
          keys: %{insert: list()} | %{delete: number()} | %{}
        }
end

defmodule Yex.XmlTextEvent do
  @moduledoc """

  Event when Text type changes

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
  """
  defstruct [
    :path,
    :target,
    :delta
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t()),
          target: Yex.XmlText.t(),
          delta: Yex.Text.delta()
        }
end

defmodule Yex.WeakEvent do
  @moduledoc """

  Event when Weak type changes

  @see Yex.SharedType.observe/1
  @see Yex.SharedType.observe_deep/1
  """
  defstruct [
    :path
  ]

  @type t :: %__MODULE__{
          path: list(number() | String.t())
        }
end
