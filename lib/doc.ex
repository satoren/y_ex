defmodule Yex.Doc do
  @moduledoc """
  Document module.

  ### Important
    It is not recommended to perform operations on a single document from multiple processes simultaneously.
    If blocked by a transaction, the Beam scheduler threads may potentially deadlock.
    This limitation is due to the underlying yrs and beam specifications and may be resolved in the future.
  """

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

  @doc """
  Get or insert the xml fragment type.
  """
  def get_xml_fragment(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_xml_fragment(doc, name)
  end

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
  @spec transaction(t, origin :: term(), fun()) :: :ok | {:error, term()}
  def transaction(%__MODULE__{reference: ref} = doc, origin \\ nil, exec) do
    if cur_txn(doc) do
      raise "Transaction already in progress"
    end

    txn = Yex.Nif.doc_begin_transaction(doc, origin)
    Process.put(ref, txn)
    exec.()
    Process.delete(ref)
    Yex.Nif.commit_transaction(txn)
    :ok
  end

  @doc """
  Monitor document updates.
   You can pass metadata as an option. This value is passed as the fourth element of the message.If omitted, it will be passed as a structure of Doc itself.
  """
  @spec monitor_update(t, keyword) :: {:ok, reference()} | {:error, term()}
  def monitor_update(%__MODULE__{} = doc, opt \\ []) do
    monitor_update_v1(doc, opt)
  end

  def monitor_update_v1(%__MODULE__{} = doc, opt \\ []) do
    case Yex.Nif.doc_monitor_update_v1(doc, self(), Keyword.get(opt, :metadata, doc)) do
      {:ok, ref} ->
        # Subscription should not be automatically released by gc, so put it in the process dictionary
        Process.put(__MODULE__.Subscriptions, [ref | Process.get(__MODULE__.Subscriptions, [])])
        {:ok, ref}

      error ->
        error
    end
  end

  def monitor_update_v2(%__MODULE__{} = doc, opt \\ []) do
    case Yex.Nif.doc_monitor_update_v2(doc, self(), Keyword.get(opt, :metadata, doc)) do
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
    demonitor_update_v1(sub)
  end

  def demonitor_update_v1(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end

  def demonitor_update_v2(sub) do
    Process.put(__MODULE__.Subscriptions, Process.get() |> Enum.reject(&(&1 == sub)))
    Yex.Nif.sub_unsubscribe(sub)
  end

  defp cur_txn(%__MODULE__{reference: ref}) do
    Process.get(ref, nil)
  end
end
