defmodule Yex.UndoServer do
  @moduledoc """
  Define a `Yex.UndoServer` process.

  `UndoServer` defines a module to handle undo/redo operations and their observers.
  """
  alias Yex.UndoServer.State

  @type option :: {:undo_manager, Yex.UndoManager.t()} | {:assigns, map()} | {term(), term()}
  @type options :: [option()]

  @doc """
  Starts an UndoServer process linked to the current process.
  """
  def start_link(args) do
    {module, args} = Keyword.pop!(args, :module)
    GenServer.start_link(Yex.UndoServer.Worker, [{:module, module} | args])
  end

  @callback init(arg :: term, state :: State.t()) ::
              {:ok, State.t()} | {:stop, reason :: term}

  @callback handle_stack_item_added(stack_item :: Yex.UndoManager.StackItem.t(), state :: State.t()) ::
              {:ok, updated_stack_item :: Yex.UndoManager.StackItem.t(), State.t()} | {:ignore, State.t()}

  @callback handle_stack_item_popped(state :: State.t()) ::
              {:ok, State.t()} | {:stop, reason :: term, State.t()}

  @optional_callbacks init: 2,
                      handle_stack_item_added: 2,
                      handle_stack_item_popped: 1

  @spec __using__() ::
          {:__block__, [],
           [
             {:@, [...], [...]}
             | {:def, [...], [...]}
             | {:defoverridable, [...], [...]}
             | {:import, [...], [...]},
             ...
           ]}
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__)
      import Yex.UndoServer.State, only: [assign: 3, assign: 2]

      def init(_arg, state), do: {:ok, state}
      defoverridable init: 2
    end
  end
end

defmodule Yex.UndoServer.State do
  @moduledoc """
  Provides the `State` struct and functions to manage the internal state of `Yex.UndoServer`.
  """
  defstruct undo_manager: nil, assigns: %{}, module: nil

  @type t :: %__MODULE__{
          assigns: map,
          undo_manager: Yex.UndoManager.t(),
          module: module()
        }

  def assign(state, key, value) do
    assign(state, [{key, value}])
  end

  def assign(state, attrs) when is_map(attrs) or is_list(attrs) do
    %{state | assigns: Map.merge(state.assigns, Map.new(attrs))}
  end
end
