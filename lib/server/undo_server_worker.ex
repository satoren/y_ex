defmodule Yex.UndoServer.Worker do
  @moduledoc false
  use GenServer, restart: :temporary
  require Logger

  alias Yex.UndoServer.State

  @impl true
  def init(arg) do
    module = Keyword.fetch!(arg, :module)
    undo_manager = Keyword.fetch!(arg, :undo_manager)
    assigns = Keyword.get(arg, :assigns, %{})

    if function_exported?(module, :handle_stack_item_added, 2) or
         function_exported?(module, :handle_stack_item_popped, 1) do
      Yex.Nif.undo_manager_add_observer(undo_manager, module, self())
    end

    module.init(arg, %State{
      assigns: assigns,
      undo_manager: undo_manager,
      module: module
    })
  end

  @impl true
  def handle_info({:stack_item_added, %Yex.UndoManager.StackItem{} = stack_item}, %{module: module} = state) do
    case module.handle_stack_item_added(stack_item, state) do
      {:ok, %Yex.UndoManager.StackItem{} = updated_item, new_state} ->
        Yex.Nif.undo_manager_update_stack_item(state.undo_manager, updated_item)
        {:noreply, new_state}
      {:ignore, new_state} ->
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:stack_item_popped, _meta}, %{module: module} = state) do
    case module.handle_stack_item_popped(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:stop, reason, new_state} -> {:stop, reason, new_state}
    end
  end
end
