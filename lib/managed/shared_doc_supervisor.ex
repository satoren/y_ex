defmodule Yex.Managed.SharedDocSupervisor do
  @moduledoc """
  This module is experimental

  Supervisor for SharedDoc
  """

  alias Yex.Managed.SharedDoc
  use Supervisor

  defmodule LocalPubsub do
    @moduledoc """
    default implementation for local pubsub

    Used to notify SharedDoc users of updates.
    """
    @behaviour Yex.Managed.SharedDoc.LocalPubSubBehaviour

    def monitor_count(doc_name) do
      Registry.lookup(__MODULE__, doc_name) |> Enum.count()
    end

    def broadcast(doc_name, message, exclude_origin) do
      Registry.dispatch(__MODULE__, doc_name, fn entries ->
        entries
        |> Enum.reject(fn {_pid, origin} -> origin === exclude_origin end)
        |> Enum.each(fn {pid, _origin} -> send(pid, message) end)
      end)
    end

    def monitor(doc_name) do
      {:ok, _} = Registry.register(__MODULE__, doc_name, "#{inspect(self())}")
      :ok
    end

    def demonitor(doc_name) do
      :ok = Registry.unregister(__MODULE__, doc_name)
    end
  end

  @registry Yex.Managed.SharedDocSupervisor.SharedDocRegistry
  @dynamic_supervisor Yex.Managed.SharedDocSupervisor.DynamicSupervisor

  @type launch_param ::
          {:persistence, {module() | {module(), init_arg :: term()}}}
          | {:idle_timeout, integer()}
          | {:pg_scope, atom()}
          | {:local_pubsub, module()}

  @spec start_link([launch_param]) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    pg_scope = Keyword.get(init_arg, :pg_scope, Yex.Managed.SharedDocScope)

    local_pubsub =
      Keyword.get(init_arg, :local_pubsub, Yex.Managed.SharedDocSupervisor.LocalPubsub)

    children = [
      %{
        id: :pg,
        start: {:pg, :start_link, [pg_scope]}
      },
      {Registry, keys: :unique, name: @registry},
      {Registry, keys: :duplicate, name: local_pubsub},
      {@dynamic_supervisor, [local_pubsub: local_pubsub] ++ init_arg}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_child(doc_name, start_arg \\ []) do
    name = via_name(doc_name)

    option = [doc_name: doc_name, name: name] ++ start_arg
    @dynamic_supervisor.start_child(option)

    try do
      # check started
      SharedDoc.doc_name(name)
    catch
      _ ->
        @dynamic_supervisor.start_child(option)
    end

    {:ok, name}
  end

  def via_name(doc_name) do
    {:via, Registry, {@registry, doc_name}}
  end
end

defmodule Yex.Managed.SharedDocSupervisor.DynamicSupervisor do
  @moduledoc false
  use DynamicSupervisor

  defmodule ChildSpec do
    @moduledoc false
    def start_link(extra_arguments, option) do
      name = Keyword.fetch!(option, :name)
      option = option |> Keyword.delete(:name)
      Yex.Managed.SharedDoc.start_link(option ++ extra_arguments, name: name)
    end

    def child_spec(opts) do
      %{
        id: Yex.Managed.SharedDoc,
        start: {__MODULE__, :start_link, [opts]}
      }
    end
  end

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(args) do
    spec = {
      ChildSpec,
      args
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [init_arg]
    )
  end
end
