defmodule Yex.Doc do
  defmodule Options do
    @moduledoc """
    Document options.
    """
    defstruct client_id: 0,
              guid: nil,
              collection_id: nil,
              offset_kind: :bytes,
              skip_gc: false,
              auto_load: false,
              should_load: true

    @type t :: %__MODULE__{
            client_id: integer(),
            guid: String.t() | nil,
            collection_id: String.t(),
            offset_kind: :bytes | :utf16,
            skip_gc: boolean(),
            auto_load: boolean(),
            should_load: boolean()
          }
  end

  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  @doc """
  Create a new document.
  """
  @spec new() :: Yex.Doc.t()
  def new() do
    Yex.Nif.doc_new()
  end

  @doc """
  Create a new document with options.
  """
  @spec with_options(Options.t()) :: Yex.Doc.t()
  def with_options(%Options{} = option) do
    Yex.Nif.doc_with_options(option)
  end

  @doc """
  Get or insert the text type.
  """
  @spec get_text(t, String.t()) :: Yex.Text.t()
  def get_text(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_text(doc, name)
  end

  @doc """
  Get or insert the array type.
  """
  @spec get_array(t, String.t()) :: Yex.Array.t()
  def get_array(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_array(doc, name)
  end

  @doc """
  Get or insert the map type.
  """
  @spec get_map(t, String.t()) :: Yex.Map.t()
  def get_map(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_map(doc, name)
  end

  #  def get_xml_fragment(%__MODULE__{} = _doc, _name) do
  #    raise "Not implemented"
  #  end

  @doc """
  Start a transaction.

  ## Examples
      iex> doc = Doc.new()
      iex> text = Doc.get_text(doc, "text")
      iex> Yex.Doc.monitor_update(doc)
      iex> Doc.transaction(doc, fn ->
      iex>   Text.insert(text, 0, "Hello")
      iex>   Text.insert(text, 0, "Hello", %{"bold" => true})
      iex> end)
      iex> assert_receive {:update_v1, _, nil, _}
      iex> refute_receive {:update_v1, _, nil, _} # only one update message

  """
  @spec transaction(t, fun()) :: :ok | {:error, term()}
  def transaction(%__MODULE__{} = doc, exec) do
    case Yex.Nif.doc_begin_transaction(doc, nil) do
      {:ok, _} ->
        exec.()
        Yex.Nif.doc_commit_transaction(doc)
        :ok

      error ->
        error
    end
  end

  def transaction(%__MODULE__{} = doc, origin, exec) do
    case Yex.Nif.doc_begin_transaction(doc, origin) do
      {:ok, _} ->
        exec.()
        Yex.Nif.doc_commit_transaction(doc)
        :ok

      error ->
        error
    end
  end

  @doc """
  Monitor document updates.
  """
  @spec monitor_update(t) :: {:ok, reference()} | {:error, term()}
  def monitor_update(%__MODULE__{} = doc) do
    monitor_update_v1(doc)
  end

  def monitor_update_v1(%__MODULE__{} = doc) do
    case Yex.Nif.doc_monitor_update_v1(doc, self()) do
      {:ok, ref} ->
        # Subscription should not be automatically released by gc, so put it in the process dictionary
        Process.put(__MODULE__.Subscriptions, [ref | Process.get(__MODULE__.Subscriptions, [])])
        {:ok, ref}

      error ->
        error
    end
  end

  def monitor_update_v2(%__MODULE__{} = doc) do
    case Yex.Nif.doc_monitor_update_v2(doc, self()) do
      {:ok, ref} ->
        # Subscription should not be automatically released by gc, so put it in the process dictionary
        Process.put(__MODULE__.Subscriptions, [ref | Process.get(__MODULE__.Subscriptions, [])])
        {:ok, ref}

      error ->
        error
    end
  end

  @doc """
  Stop monitoring document updates.
  """
  @spec demonitor_update(reference()) :: :ok | {:error, term()}
  def demonitor_update(sub) do
    demonitor_update_v2(sub)
  end

  def demonitor_update_v1(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end

  def demonitor_update_v2(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end
end
