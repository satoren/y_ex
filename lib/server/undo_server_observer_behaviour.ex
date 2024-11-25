defmodule Yex.UndoServer.ObserverBehavior do
  @moduledoc """
  Behaviour for implementing UndoManager observers that can track and modify
  stack items during undo/redo operations.
  """

  @callback handle_stack_item_added(stack_item :: map()) :: {:ok, map()} | :ignore
  @callback handle_stack_item_popped() :: :ok
end
