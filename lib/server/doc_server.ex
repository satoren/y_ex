defmodule Yex.DocServer do
  @moduledoc """
  Define a `Yex.DocServer` process.

  `DocServer` defines a module to handle document update messages by yjs.

  ## Examples
      defmodule MyDocServer do
        use Yex.DocServer

        def init(_arg, state) do
          {:ok, state}
        end

        def handle_update_v1(doc, update, origin, state) do
          # Handle document updates from Yjs
          # - doc: The current document state
          # - update: Binary encoded update
          # - origin: Source of the update
          {:noreply, state}
        end

        def handle_awareness_change(awareness, %{removed: removed, added: added, updated: updated}, origin, state) do
          # Handle presence/awareness changes
          # - awareness: Current awareness state
          # - removed/added/updated: Lists of changed client IDs
          {:noreply, state}
        end
      end

  """
  alias Yex.DocServer.State

  @type option :: {:doc_option, Yex.Doc.Options.t()} | {:assigns, map()} | {term(), term()}
  @type options :: [option()]

  @doc """
  Starts a `DocServer` process linked to the current process.
  """
  @callback start_link(
              arg :: options(),
              genserver_option :: GenServer.options()
            ) :: {:ok, pid()} | {:error, term()}

  @doc """
  Starts a `DocServer` process without linking (for use outside of a supervision tree).

  Returns the same success and error responses as `start_link/2`.
  """
  @callback start(
              arg :: options(),
              genserver_option :: GenServer.options()
            ) :: {:ok, pid()} | {:error, term()}

  @doc """
  Interprets and processes v1 encode message.

  """
  @callback process_message_v1(
              server :: GenServer.server(),
              message :: binary(),
              origin :: binary()
            ) :: :ok | {:ok, replies :: list(binary())} | {:error, term()}

  @doc """
  Handle document updates in v1 encoding format.

  ## Parameters
  - doc: Current document state
  - update: Binary encoded update from Yjs
  - origin: Source of the update (can be nil for local updates)
  - state: Current server state

  ## Returns
  - `{:noreply, state}` to continue with new state
  - `{:stop, reason, state}` to stop the server

  """
  @callback handle_update_v1(
              doc :: Yex.Doc.t(),
              update :: binary(),
              origin :: binary(),
              state :: State.t()
            ) ::
              {:noreply, State.t()}
              | {:stop, reason :: term, State.t()}

  @doc """
  Handle awareness change

  """
  @callback handle_awareness_change(
              awareness :: Yex.Awareness.t(),
              update :: %{removed: list(), added: list(), updated: list()},
              origin :: binary(),
              state :: State.t()
            ) ::
              {:noreply, State.t()}
              | {:stop, reason :: term, State.t()}

  @doc """
  Initialize the doc process.

  """
  @callback init(arg :: term, state :: State.t()) ::
              {:ok, State.t()}
              | {:stop, reason :: term}

  @doc """
  Handle regular Elixir process messages.

  See `c:GenServer.handle_info/2`.
  """
  @callback handle_info(msg :: term, state :: State.t()) ::
              {:noreply, State.t()}
              | {:stop, reason :: term, State.t()}

  @doc """
  Handle regular GenServer call messages.

  See `c:GenServer.handle_call/3`.
  """
  @callback handle_call(msg :: term, from :: {pid, tag :: term}, state :: State.t()) ::
              {:reply, response :: term, State.t()}
              | {:noreply, State.t()}
              | {:stop, reason :: term, State.t()}

  @doc """
  Handle regular GenServer cast messages.

  See `c:GenServer.handle_cast/2`.
  """
  @callback handle_cast(msg :: term, state :: State.t()) ::
              {:noreply, State.t()}
              | {:stop, reason :: term, State.t()}

  @doc """
  Invoked when the document server process is about to exit.

  See `c:GenServer.terminate/2`.
  """
  @callback terminate(
              reason :: :normal | :shutdown | {:shutdown, :left | :closed | term},
              state :: State.t()
            ) ::
              term

  @optional_callbacks init: 2,
                      handle_info: 2,
                      handle_call: 3,
                      handle_cast: 2,
                      terminate: 2,
                      handle_update_v1: 4,
                      handle_awareness_change: 4

  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__)
      import Yex.DocServer.State, only: [assign: 3, assign: 2]

      def child_spec(arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      def start_link(arg, opt \\ []) do
        GenServer.start_link(Yex.DocServer.Worker, [{:module, __MODULE__} | arg], opt)
      end

      def start(arg, opt \\ []) do
        GenServer.start(Yex.DocServer.Worker, [{:module, __MODULE__} | arg], opt)
      end

      def process_message_v1(server, message, origin \\ nil) do
        Yex.DocServer.Worker.process_message_v1(server, message, origin)
      end

      defoverridable child_spec: 1
    end
  end
end

defmodule Yex.DocServer.State do
  @moduledoc """
  Provides the `State` struct and functions to manage the internal state of `Yex.DocServer`.

  This module allows tracking the state of `Yex.DocServer` through a structured `State` record.
  It includes functions for assigning and updating state attributes with custom key-value pairs.
  """
  defstruct doc: nil, assigns: %{}, module: nil, awareness: nil

  @type t :: %__MODULE__{
          assigns: map,
          doc: Yex.Doc.t(),
          awareness: Yex.Awareness.t() | nil,
          module: module()
        }

  @doc """
  Assigns a single key-value pair to the `assigns` map in the state.

  This function allows for adding or updating a specific attribute in the
  state, useful for tracking individual properties in `Yex.DocServer`.
  """
  @spec assign(t(), term(), term()) :: t()
  def assign(state, key, value) do
    assign(state, [{key, value}])
  end

  @doc """
  Assigns multiple key-value pairs to the `assigns` map in the state.

  This function accepts a list or map of attributes to update the state in
  bulk, allowing for more comprehensive state updates at once.
  """
  @spec assign(t(), [{term(), term()}] | map()) :: t()
  def assign(state, attrs)
      when is_map(attrs) or is_list(attrs) do
    %{state | assigns: Map.merge(state.assigns, Map.new(attrs))}
  end
end
