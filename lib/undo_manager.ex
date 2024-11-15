defmodule Yex.UndoManager do
  @type t :: %__MODULE__{
    doc: Yex.Doc.t(),
    manager: reference(),
    options: Options.t()
  }

  defstruct [:doc, :manager, :options]

  defmodule Options do
    @default_timeout 500

    @type t :: %__MODULE__{
      capture_timeout_millis: non_neg_integer(),
      tracked_origins: [String.t()]
    }

    defstruct capture_timeout_millis: @default_timeout,
              tracked_origins: []

    def new(opts \\ []) do
      timeout = Keyword.get(opts, :capture_timeout_millis, @default_timeout)
      origins = Keyword.get(opts, :tracked_origins, [])

      %__MODULE__{
        capture_timeout_millis: timeout,
        tracked_origins: origins |> List.wrap() |> Enum.map(&to_string/1)
      }
    end
  end

  def new(doc, shared_type, opts \\ []) do
    options = Options.new(opts)

    case Yex.Nif.undo_manager_new(doc, shared_type, options) do
      {:ok, undo_manager} ->
        %__MODULE__{
          doc: doc,
          manager: undo_manager.manager,
          options: options
        }

      {:error, reason} ->
        raise ArgumentError, message: reason
    end
  end

  def include_origin(%{manager: manager} = _undo_manager, origin) when is_binary(origin) do
    case Yex.Nif.undo_manager_include_origin(manager, origin) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, message: reason
    end
  end

  def exclude_origin(%{manager: manager} = _undo_manager, origin) when is_binary(origin) do
    case Yex.Nif.undo_manager_exclude_origin(manager, origin) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, message: reason
    end
  end

  @doc """
  Undo the last change.
  """
  @spec undo(t()) :: :ok | {:error, term()}
  def undo(%{manager: manager} = _undo_manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_undo(manager, nil)
    end)
  end

  @doc """
  Redo the last undone change.
  """
  @spec redo(t()) :: :ok | {:error, term()}
  def redo(%{manager: manager} = _undo_manager) do
    Yex.Doc.transaction(manager.doc, nil, fn ->
      Yex.Nif.undo_manager_redo(manager, nil)
    end)
  end

  @doc """
  Check if there are any changes that can be undone.
  """
  @spec can_undo?(t()) :: boolean()
  def can_undo?(%{manager: manager} = _undo_manager) do
    Yex.Nif.undo_manager_can_undo(manager)
  end

  @doc """
  Check if there are any changes that can be redone.
  """
  @spec can_redo?(t()) :: boolean()
  def can_redo?(%{manager: manager} = _undo_manager) do
    Yex.Nif.undo_manager_can_redo(manager)
  end

  @doc """
  Clear all undo/redo history.
  """
  @spec clear(t()) :: :ok | {:error, term()}
  def clear(%{manager: manager} = _undo_manager) do
    Yex.Nif.undo_manager_clear(manager)
  end

  @doc """
  Add an origin to track for undo/redo operations.
  """
  @spec add_tracked_origin(t(), term()) :: :ok
  def add_tracked_origin(%{manager: manager} = _undo_manager, origin) do
    Yex.Nif.undo_manager_add_tracked_origin(manager, origin)
  end

  @doc """
  Remove an origin from tracking.
  """
  @spec remove_tracked_origin(t(), term()) :: :ok
  def remove_tracked_origin(%{manager: manager} = _undo_manager, origin) do
    Yex.Nif.undo_manager_remove_tracked_origin(manager, origin)
  end
end
