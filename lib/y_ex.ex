defmodule Yex do
  @moduledoc """
  Yex is wrapper library for the Yjs CRDT library.
  """

  require Yex.Doc
  import Yex.Doc, only: [cur_txn: 1]

  @type any_type ::
          binary
          | map
          | list
          | integer
          | float
          | boolean
          | nil
  @type input_type ::
          any_type
          | Yex.PrelimType.t()

  @doc """
  Computes the state vector and encodes it into an Binary.
  A state vector describes the state of the local client.
  The remote client can use this to exchange only the missing differences.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_vector(doc)
  """
  @spec encode_state_vector(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector(%Yex.Doc{} = doc) do
    encode_state_vector_v1(doc)
  end

  @doc """
  @see encode_state_vector/1
  """
  @spec encode_state_vector!(Yex.Doc.t()) :: binary()
  def encode_state_vector!(%Yex.Doc{} = doc) do
    case encode_state_vector(doc) do
      {:ok, binary} -> binary
      {:error, reason} -> raise RuntimeError, message: inspect(reason)
    end
  end

  @doc """
  Computes the state vector and encodes it with the v1 format.

  Same as `encode_state_vector/1`.
  """
  @spec encode_state_vector_v1(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector_v1(%Yex.Doc{} = doc) do
    Yex.Doc.run_in_worker_process doc do
      Yex.Nif.encode_state_vector_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Computes the state vector and encodes it with the v2 format.

  This is the yrs v2 framing, which yjs peers cannot read. The update utilities such as
  `diff_update_v2/2` take the v1 encoding from `encode_state_vector_v1/1`.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_vector_v2(doc)
  """
  @spec encode_state_vector_v2(Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector_v2(%Yex.Doc{} = doc) do
    Yex.Doc.run_in_worker_process doc do
      Yex.Nif.encode_state_vector_v2(doc, cur_txn(doc))
    end
  end

  @doc """
  Encode the document state as a single update message that can be applied on the remote document. Optionally, specify the target state vector to only write the missing differences to the update message.

  Returns `{:error, {:encoding_exception, message}}` when `encoded_state_vector` cannot be
  decoded.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_as_update(doc)
  """
  @spec encode_state_as_update(Yex.Doc.t(), binary() | nil) :: {:ok, binary()} | {:error, term()}
  def encode_state_as_update(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    encode_state_as_update_v1(doc, encoded_state_vector)
  end

  @doc """
  @see encode_state_as_update/2
  """
  @spec encode_state_as_update!(Yex.Doc.t(), binary() | nil) :: binary()
  def encode_state_as_update!(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    case encode_state_as_update(doc, encoded_state_vector) do
      {:ok, binary} -> binary
      {:error, {:encoding_exception, message}} -> raise ArgumentError, message: message
      {:error, reason} -> raise RuntimeError, message: inspect(reason)
    end
  end

  @doc """
  Encodes the document state as a v1 update.

  Same as `encode_state_as_update/2`. `encoded_state_vector` must be v1 encoded.

  Returns `{:error, {:encoding_exception, message}}` when `encoded_state_vector` cannot be
  decoded.
  """
  @spec encode_state_as_update_v1(Yex.Doc.t(), binary() | nil) ::
          {:ok, binary()} | {:error, term()}
  def encode_state_as_update_v1(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    Yex.Doc.run_in_worker_process doc do
      txn = cur_txn(doc)

      case Yex.Nif.encode_state_as_update_v1(
             doc,
             txn,
             encoded_state_vector,
             Yex.Nif.dirty_encode_items()
           ) do
        :dirty -> Yex.Nif.encode_state_as_update_v1_dirty(doc, txn, encoded_state_vector)
        result -> result
      end
    end
  end

  @doc false
  @spec encode_diff_and_state_vector_v1(Yex.Doc.t(), binary()) ::
          {:ok, binary(), binary()} | {:error, term()}
  def encode_diff_and_state_vector_v1(%Yex.Doc{} = doc, remote_encoded_state_vector)
      when is_binary(remote_encoded_state_vector) do
    Yex.Doc.run_in_worker_process doc do
      txn = cur_txn(doc)
      sv = remote_encoded_state_vector

      case Yex.Nif.encode_diff_and_state_vector_v1(doc, txn, sv, Yex.Nif.dirty_encode_items()) do
        :dirty -> Yex.Nif.encode_diff_and_state_vector_v1_dirty(doc, txn, sv)
        result -> result
      end
    end
  end

  @doc """
  Encodes the document state as a v2 update.

  Optionally, pass a v2 encoded state vector (see `encode_state_vector_v2/1`)
  to only write the missing differences.

  Returns `{:error, {:encoding_exception, message}}` when `encoded_state_vector` cannot be
  decoded.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> {:ok, _binary} = Yex.encode_state_as_update_v2(doc)
  """
  @spec encode_state_as_update_v2(Yex.Doc.t(), binary() | nil) ::
          {:ok, binary()} | {:error, term()}
  def encode_state_as_update_v2(%Yex.Doc{} = doc, encoded_state_vector \\ nil) do
    Yex.Doc.run_in_worker_process doc do
      txn = cur_txn(doc)

      case Yex.Nif.encode_state_as_update_v2(
             doc,
             txn,
             encoded_state_vector,
             Yex.Nif.dirty_encode_items()
           ) do
        :dirty -> Yex.Nif.encode_state_as_update_v2_dirty(doc, txn, encoded_state_vector)
        result -> result
      end
    end
  end

  @doc """
  Apply a document update on the shared document.

  Returns `{:error, {:encoding_exception, message}}` when `update` cannot be decoded.

  ## Examples syncs two clients by exchanging the complete document structure
      iex> doc1 = Yex.Doc.new()
      iex> doc2 = Yex.Doc.new()
      iex> {:ok, state1} = Yex.encode_state_as_update(doc1)
      iex> {:ok, state2} = Yex.encode_state_as_update(doc2)
      iex> Yex.apply_update(doc1, state2)
      :ok
      iex> Yex.apply_update(doc2, state1)
      :ok
  """
  @spec apply_update(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update(%Yex.Doc{} = doc, update) do
    apply_update_v1(doc, update)
  end

  @doc """
  Applies a v1 encoded update to the document.

  Same as `apply_update/2`.

  Returns `{:error, {:encoding_exception, message}}` when `update` cannot be decoded.
  """
  @spec apply_update_v1(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update_v1(%Yex.Doc{} = doc, update) do
    Yex.Doc.run_in_worker_process doc do
      if byte_size(update) > Yex.Nif.dirty_cutoff(),
        do: Yex.Nif.apply_update_v1_dirty(doc, cur_txn(doc), update),
        else: Yex.Nif.apply_update_v1(doc, cur_txn(doc), update)
    end
  end

  @doc """
  Applies a v2 encoded update to the document.

  Returns `{:error, {:encoding_exception, message}}` when `update` cannot be decoded.

  ## Examples
      iex> doc1 = Yex.Doc.new()
      iex> doc2 = Yex.Doc.new()
      iex> Yex.Text.insert(Yex.Doc.get_text(doc1, "text"), 0, "Hello")
      iex> {:ok, update} = Yex.encode_state_as_update_v2(doc1)
      iex> Yex.apply_update_v2(doc2, update)
      :ok
      iex> Yex.Text.to_string(Yex.Doc.get_text(doc2, "text"))
      "Hello"
  """
  @spec apply_update_v2(Yex.Doc.t(), binary()) :: :ok | {:error, term()}
  def apply_update_v2(%Yex.Doc{} = doc, update) do
    Yex.Doc.run_in_worker_process doc do
      if byte_size(update) > Yex.Nif.dirty_cutoff(),
        do: Yex.Nif.apply_update_v2_dirty(doc, cur_txn(doc), update),
        else: Yex.Nif.apply_update_v2(doc, cur_txn(doc), update)
    end
  end

  @doc """
  Merges multiple v1 encoded updates into a single update.

  The result is equivalent to applying all updates in order, without needing a document.
  Same as `merge_updates_v1/1`.

  Returns `{:error, {:encoding_exception, message}}` when an update cannot be decoded.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Doc.monitor_update(doc)
      iex> Yex.Text.insert(text, 0, "Hello")
      iex> Yex.Text.insert(text, 5, " World")
      iex> assert_receive {:update_v1, update1, _, _}
      iex> assert_receive {:update_v1, update2, _, _}
      iex> {:ok, merged} = Yex.merge_updates([update1, update2])
      iex> doc2 = Yex.Doc.new()
      iex> Yex.apply_update(doc2, merged)
      iex> Yex.Text.to_string(Yex.Doc.get_text(doc2, "text"))
      "Hello World"
  """
  @spec merge_updates([binary()]) :: {:ok, binary()} | {:error, term()}
  def merge_updates(updates) when is_list(updates) do
    merge_updates_v1(updates)
  end

  @doc """
  Merges multiple v1 encoded updates into a single v1 update.

  Same as `merge_updates/1`.

  Returns `{:error, {:encoding_exception, message}}` when an update cannot be decoded.
  """
  @spec merge_updates_v1([binary()]) :: {:ok, binary()} | {:error, term()}
  def merge_updates_v1(updates) when is_list(updates) do
    if IO.iodata_length(updates) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.merge_updates_v1_dirty(updates),
      else: Yex.Nif.merge_updates_v1(updates)
  end

  @doc """
  Merges multiple v2 encoded updates into a single v2 update.

  Returns `{:error, {:encoding_exception, message}}` when an update cannot be decoded.
  """
  @spec merge_updates_v2([binary()]) :: {:ok, binary()} | {:error, term()}
  def merge_updates_v2(updates) when is_list(updates) do
    if IO.iodata_length(updates) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.merge_updates_v2_dirty(updates),
      else: Yex.Nif.merge_updates_v2(updates)
  end

  @doc """
  Parses an update payload encoded in lib0 v1 format and returns a human-readable debug string.

  Returns `{:error, {:encoding_exception, message}}` when `update` cannot be decoded.
  """
  @spec update_debug_v1(binary()) :: {:ok, String.t()} | {:error, term()}
  def update_debug_v1(update) when is_binary(update) do
    Yex.Nif.update_debug_v1(update)
  end

  @doc """
  Parses an update payload encoded in lib0 v2 format and returns a human-readable debug string.

  Returns `{:error, {:encoding_exception, message}}` when `update` cannot be decoded.
  """
  @spec update_debug_v2(binary()) :: {:ok, String.t()} | {:error, term()}
  def update_debug_v2(update) when is_binary(update) do
    Yex.Nif.update_debug_v2(update)
  end

  @doc """
  Returns the part of a v1 `update` that a peer with `state_vector` has not seen yet.

  `state_vector` is v1 encoded, as produced by `encode_state_vector_v1/1`,
  `encode_state_vector_from_update/1` or yjs `encodeStateVector`. The delete set of
  `update` is carried over whole. Same as `diff_update_v1/2`, and as yjs `diffUpdate`
  byte for byte.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "Hello")
      iex> {:ok, state_vector} = Yex.encode_state_vector(doc)
      iex> Yex.Text.insert(text, 5, " World")
      iex> {:ok, update} = Yex.encode_state_as_update(doc)
      iex> {:ok, diff} = Yex.diff_update(update, state_vector)
      iex> byte_size(diff) < byte_size(update)
      true
  """
  @spec diff_update(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def diff_update(update, state_vector), do: diff_update_v1(update, state_vector)

  @doc """
  Returns the part of a v1 `update` that a peer with the v1 `state_vector` has not seen yet.

  Same as `diff_update/2`. Unlike the other v1 update utilities, this one does not reject
  a v2 update passed by mistake; like yjs, it may read it as an empty update.
  """
  @spec diff_update_v1(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def diff_update_v1(update, state_vector) when is_binary(update) and is_binary(state_vector) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.diff_update_v1_dirty(update, state_vector),
      else: Yex.Nif.diff_update_v1(update, state_vector)
  end

  @doc """
  Returns the part of a v2 `update` that a peer with `state_vector` has not seen yet,
  as a v2 update.

  `state_vector` is v1 encoded, as in yjs `diffUpdateV2` and the sync protocol. The output
  of `encode_state_vector_v2/1` is a different encoding and reads here as the empty state
  vector, so the whole update comes back; use `encode_state_vector_v1/1` instead.
  """
  @spec diff_update_v2(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def diff_update_v2(update, state_vector) when is_binary(update) and is_binary(state_vector) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.diff_update_v2_dirty(update, state_vector),
      else: Yex.Nif.diff_update_v2(update, state_vector)
  end

  @doc """
  Returns the v1 encoded state vector of a v1 `update`.

  A client counts only up to the first gap in its clocks: a client whose structs do not
  start at clock 0 is left out, as in yjs `encodeStateVectorFromUpdate`. Same as
  `encode_state_vector_from_update_v1/1`.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1})
      iex> Yex.Text.insert(Yex.Doc.get_text(doc, "text"), 0, "Hello")
      iex> {:ok, update} = Yex.encode_state_as_update(doc)
      iex> {:ok, state_vector} = Yex.encode_state_vector_from_update(update)
      iex> Yex.decode_state_vector(state_vector)
      {:ok, %{1 => 5}}
  """
  @spec encode_state_vector_from_update(binary()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector_from_update(update), do: encode_state_vector_from_update_v1(update)

  @doc """
  Returns the v1 encoded state vector of a v1 `update`.

  Same as `encode_state_vector_from_update/1`. Input left over after the update, such as
  a v2 update passed by mistake, returns `{:error, {:encoding_exception, _}}`; yjs does
  not check this.
  """
  @spec encode_state_vector_from_update_v1(binary()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector_from_update_v1(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.encode_state_vector_from_update_v1_dirty(update),
      else: Yex.Nif.encode_state_vector_from_update_v1(update)
  end

  @doc """
  Returns the state vector of a v2 `update`, v1 encoded.

  The result is v1 encoded like yjs `encodeStateVectorFromUpdateV2`, so it can be passed
  to `diff_update_v2/2` and to yjs peers. It is not the encoding `encode_state_vector_v2/1`
  returns.
  """
  @spec encode_state_vector_from_update_v2(binary()) :: {:ok, binary()} | {:error, term()}
  def encode_state_vector_from_update_v2(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.encode_state_vector_from_update_v2_dirty(update),
      else: Yex.Nif.encode_state_vector_from_update_v2(update)
  end

  @doc """
  Re-encodes a v1 update as a v2 update without changing its content.

  The output matches yjs `convertUpdateFormatV1ToV2` byte for byte. Input left over after
  the update, such as a v2 update passed by mistake, returns
  `{:error, {:encoding_exception, _}}` instead of an empty update.
  """
  @spec convert_update_format_v1_to_v2(binary()) :: {:ok, binary()} | {:error, term()}
  def convert_update_format_v1_to_v2(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.convert_update_format_v1_to_v2_dirty(update),
      else: Yex.Nif.convert_update_format_v1_to_v2(update)
  end

  @doc """
  Re-encodes a v2 update as a v1 update without changing its content.

  The output matches yjs `convertUpdateFormatV2ToV1` byte for byte.
  """
  @spec convert_update_format_v2_to_v1(binary()) :: {:ok, binary()} | {:error, term()}
  def convert_update_format_v2_to_v1(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.convert_update_format_v2_to_v1_dirty(update),
      else: Yex.Nif.convert_update_format_v2_to_v1(update)
  end

  @doc """
  Returns the clock range each client's structs cover in a v1 `update`.

  `from` maps each client to the clock of its first struct and `to` to the end (exclusive)
  of its last one, as in yjs `parseUpdateMeta`. The delete set is not counted, so an
  update that only deletes returns empty maps. Same as `parse_update_meta_v1/1`.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1})
      iex> Yex.Text.insert(Yex.Doc.get_text(doc, "text"), 0, "Hello")
      iex> {:ok, update} = Yex.encode_state_as_update(doc)
      iex> Yex.parse_update_meta(update)
      {:ok, %{from: %{1 => 0}, to: %{1 => 5}}}
  """
  @spec parse_update_meta(binary()) ::
          {:ok,
           %{
             from: %{non_neg_integer() => non_neg_integer()},
             to: %{non_neg_integer() => non_neg_integer()}
           }}
          | {:error, term()}
  def parse_update_meta(update), do: parse_update_meta_v1(update)

  @doc """
  Returns the clock range each client's structs cover in a v1 `update`.

  Same as `parse_update_meta/1`. Input left over after the update, such as a v2 update
  passed by mistake, returns `{:error, {:encoding_exception, _}}`.
  """
  @spec parse_update_meta_v1(binary()) ::
          {:ok,
           %{
             from: %{non_neg_integer() => non_neg_integer()},
             to: %{non_neg_integer() => non_neg_integer()}
           }}
          | {:error, term()}
  def parse_update_meta_v1(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.parse_update_meta_v1_dirty(update),
      else: Yex.Nif.parse_update_meta_v1(update)
  end

  @doc """
  Returns the clock range each client's structs cover in a v2 `update`.

  See `parse_update_meta/1`.
  """
  @spec parse_update_meta_v2(binary()) ::
          {:ok,
           %{
             from: %{non_neg_integer() => non_neg_integer()},
             to: %{non_neg_integer() => non_neg_integer()}
           }}
          | {:error, term()}
  def parse_update_meta_v2(update) when is_binary(update) do
    if byte_size(update) > Yex.Nif.dirty_cutoff(),
      do: Yex.Nif.parse_update_meta_v2_dirty(update),
      else: Yex.Nif.parse_update_meta_v2(update)
  end

  @doc """
  Decodes a v1 encoded state vector into a map of client id to clock.

  Accepts the output of `encode_state_vector_v1/1`, `encode_state_vector_from_update/1`
  and yjs `encodeStateVector`, like yjs `decodeStateVector`.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{client_id: 1})
      iex> Yex.Text.insert(Yex.Doc.get_text(doc, "text"), 0, "Hello")
      iex> Yex.decode_state_vector(Yex.encode_state_vector!(doc))
      {:ok, %{1 => 5}}
  """
  @spec decode_state_vector(binary()) ::
          {:ok, %{non_neg_integer() => non_neg_integer()}} | {:error, term()}
  def decode_state_vector(state_vector) when is_binary(state_vector) do
    Yex.Nif.decode_state_vector(state_vector)
  end

  @doc """
  Returns the pending update (v1 encoded) for the document, if any.

  A pending update accumulates operations that arrived out of order and
  could not yet be applied because their causal predecessors are missing.
  Returns `{:ok, binary()}` when a pending update exists, `{:ok, nil}` otherwise.
  """
  @spec get_pending_update(Yex.Doc.t()) :: {:ok, binary() | nil} | {:error, term()}
  def get_pending_update(%Yex.Doc{} = doc) do
    Yex.Doc.run_in_worker_process doc do
      Yex.Nif.get_pending_update_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Returns the pending delete set (v1 encoded) for the document, if any.

  A pending delete set holds deletions that arrived out of order and could
  not yet be applied. Returns `{:ok, binary()}` when a pending delete set
  exists, `{:ok, nil}` otherwise.
  """
  @spec get_pending_ds(Yex.Doc.t()) :: {:ok, binary() | nil} | {:error, term()}
  def get_pending_ds(%Yex.Doc{} = doc) do
    Yex.Doc.run_in_worker_process doc do
      Yex.Nif.get_pending_ds_v1(doc, cur_txn(doc))
    end
  end

  @doc """
  Creates a snapshot of the current document state.

  The returned snapshot can later be used with
  `Yex.Snapshot.encode_state_v1/1` or `Yex.Snapshot.encode_state_v2/1`
  to produce a time-travel update for that point-in-time state.

  The source document must have garbage collection disabled
  (`Yex.Doc.Options.skip_gc == true`) for snapshot-based time-travel encoding.
  """
  @spec snapshot(Yex.Doc.t()) :: {:ok, Yex.Snapshot.t()} | {:error, term()}
  def snapshot(%Yex.Doc{} = doc) do
    Yex.Doc.run_in_worker_process doc do
      Yex.Nif.transaction_snapshot(doc, cur_txn(doc))
    end
  end

  @doc """
  Normalize a number to a format that can be used in Yjs.
  """
  def normalize(number) when is_number(number) do
    Yex.Nif.normalize_number(number)
  end

  def normalize(number) do
    number
  end
end
