defmodule Yex.DocServer do
  defmodule State do
    defstruct assigns: %{},
              doc: nil,
              awareness: nil,
              module: nil

    @type t :: %Yex.DocServer.State{
            assigns: map,
            doc: Yex.Doc.t(),
            awareness: Yex.Awareness.t() | nil,
            module: module()
          }

    @doc """
    Assigns a key-value pair to the state.

    """
    @spec assign(%State{}, term(), term()) :: %State{}
    def assign(%State{} = state, key, value) do
      assign(state, [{key, value}])
    end

    @doc """
     Assigns a list of key-value pairs to the state.
    """
    @spec assign(%State{}, [{term(), term()}] | map()) :: %State{}
    def assign(%State{} = state, attrs)
        when is_map(attrs) or is_list(attrs) do
      %{state | assigns: Map.merge(state.assigns, Map.new(attrs))}
    end
  end

  @type option :: {:doc_option, Yex.Doc.Options.t(), assigns: map()}

  @doc """
  Starts a DocServer process linked to the current process.
  """
  @callback start_link(
              arg :: option(),
              genserver_option :: GenServer.options()
            ) :: {:ok, replies :: list(binary())} | {:error, term()}

  @doc """
  Starts a DocServer process without links (outside of a supervision tree).
  """
  @callback start(
              arg :: option(),
              genserver_option :: GenServer.options()
            ) :: {:ok, replies :: list(binary())} | {:error, term()}

  @doc """
  Interprets and processes v1 encode message.

  """
  @callback process_message_v1(
              server :: GenServer.server(),
              message :: binary(),
              origin :: binary()
            ) :: :ok | {:ok, replies :: list(binary())} | {:error, term()}

  @doc """
  Handle document update v1 encode.

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
  Handle document update v1 encode.

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
  Invoked when the channel process is about to exit.

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
      import State, only: [assign: 3, assign: 2]

      def child_spec(init_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [init_arg]},
          restart: :temporary
        }
      end

      @type arg :: {:doc_option, Yex.Doc.Options.t()}
      def start_link(arg, opt \\ []) do
        GenServer.start_link(Yex.DocServer.Handler, Keyword.put(arg, :module, __MODULE__), opt)
      end

      def start(arg, opt \\ []) do
        GenServer.start(Yex.DocServer.Handler, Keyword.put(arg, :module, __MODULE__), opt)
      end

      def process_message_v1(server, message, origin \\ nil) do
        Yex.DocServer.Handler.process_message_v1(server, message, origin)
      end
    end
  end
end
