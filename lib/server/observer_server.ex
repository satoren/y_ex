defmodule Yex.ObserverServer do
  @moduledoc """
  Defines a server process to handle undo/redo operations and their observers.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Yex.ObserverServer.State

  @type option :: {:undo_manager, Yex.UndoManager.t()} | {:assigns, map()} | {term(), term()}
  @type options :: [option()]

  # Behavior callbacks
  @callback init(arg :: term, state :: State.t()) ::
              {:ok, State.t()} | {:stop, reason :: term}


  # currently handlers for UndoManager.  Expect to be extended for all necessary Observer handlers
  @callback handle_stack_item_added(stack_item :: Yex.UndoManager.StackItem.t(), state :: State.t()) ::
              {:ok, updated_stack_item :: Yex.UndoManager.StackItem.t(), State.t()} | {:ignore, State.t()}

  @callback handle_stack_item_popped(state :: State.t()) ::
              {:ok, State.t()} | {:stop, reason :: term, State.t()}

  @optional_callbacks init: 2,
                     handle_stack_item_added: 2,
                     handle_stack_item_popped: 1


  # Public API
  def start_link(args) do
    {module, args} = Keyword.pop!(args, :module)
    GenServer.start_link(__MODULE__, [{:module, module} | args])
  end

  # GenServer callbacks
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

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__)
      import Yex.ObserverServer.State, only: [assign: 3, assign: 2]

      def init(_arg, state), do: {:ok, state}
      defoverridable init: 2
    end
  end
end
