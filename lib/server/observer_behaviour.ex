defmodule Yex.ObserverServer.ObserverBehavior do
  @moduledoc """
  Behaviour for implementing UndoManager observers that can track and modify
  stack items during undo/redo operations.
  """

  @doc """
  Called when a new item is about to be added to the undo stack.

  ## Parameters
  - stack_item: A map containing the undo operation details

  ## Returns
  - `{:ok, modified_item}` to add the possibly modified item to the stack
  - `:ignore` to prevent the item from being added to the stack
  """
  @callback handle_stack_item_added(stack_item :: map()) :: {:ok, map()} | :ignore

  @doc """
  Called after an item has been popped from the undo stack during undo/redo operations.

  ## Returns
  - `:ok` to acknowledge the pop operation
  """
  @callback handle_stack_item_popped() :: :ok
end
