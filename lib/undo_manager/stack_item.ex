defmodule Yex.UndoManager.StackItem do
  @moduledoc """
  Represents a stack item in the UndoManager with associated metadata.
  """
  defstruct [:meta]

  @type t :: %__MODULE__{
    meta: map()
  }
end
