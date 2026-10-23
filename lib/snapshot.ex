defmodule Yex.Snapshot do
  @moduledoc """
  Snapshot of a document state at a point in time: its state vector and delete set.

  Use `Yex.snapshot/1` to take one, `encode_v1/1` / `decode_v1/1` (or the v2 pair) to
  persist it, `encode_state_v1/2` or `create_doc/3` to restore the state it describes,
  and `Yex.Text.to_delta/3` / `Yex.XmlText.to_delta/3` to show the text changes between
  two snapshots.

  Reading a document through a snapshot needs the deleted content, so the document must
  have garbage collection disabled (`Yex.Doc.Options.skip_gc == true`).

  The struct is opaque. `doc` is the document the snapshot was taken from, or `nil` for a
  decoded snapshot. `reference` holds the snapshot's lib0 v1 bytes; use `encode_v1/1` or
  `equal?/2` rather than reading it, since a struct kept from an older y_ex may hold them
  in a different order.

  Arrays, maps and XML elements have no snapshot readers (yrs has none); restore the state
  with `create_doc/3` and read it there.
  """

  alias Yex.Doc
  require Yex.Doc
  import Yex.Doc, only: [cur_txn: 1]

  defstruct [:doc, :reference]

  @opaque t :: %__MODULE__{
            doc: Yex.Doc.t() | nil,
            reference: binary()
          }

  @doc """
  Encodes the snapshot itself in lib0 v1 format, byte-identical to yjs `encodeSnapshot`.

  y_ex 0.13.0 and earlier wrote these bytes in yrs order, which differs from yjs for
  documents with several clients. Such bytes, and `%Yex.Snapshot{}` structs kept from
  those versions (for example with `:erlang.term_to_binary/1`), are re-canonicalised by
  this function and by `equal?/2`. A hand-built struct whose `reference` does not decode
  raises `ArgumentError`.

  ## Examples
      iex> {:ok, snapshot} = Yex.Snapshot.decode_v1(<<0, 1, 1, 3>>)
      iex> Yex.Snapshot.encode_v1(snapshot)
      {:ok, <<0, 1, 1, 3>>}
  """
  @spec encode_v1(t()) :: {:ok, binary()}
  def encode_v1(%__MODULE__{reference: reference}), do: Yex.Nif.snapshot_encode_v1(reference)

  @doc """
  Encodes the snapshot itself in lib0 v2 format, byte-identical to yjs `encodeSnapshotV2`.

  This is not the yrs/ywasm `Snapshot::encode_v2` format, which yjs cannot read.
  """
  @spec encode_v2(t()) :: {:ok, binary()}
  def encode_v2(%__MODULE__{reference: reference}), do: Yex.Nif.snapshot_encode_v2(reference)

  @doc """
  Decodes a snapshot encoded in lib0 v1 format (yjs `encodeSnapshot`, yrs `encode_v1`).

  The returned snapshot is not bound to a document (`doc: nil`).

  ## Examples
      iex> {:ok, %Yex.Snapshot{doc: nil}} = Yex.Snapshot.decode_v1(<<0, 0>>)
      iex> {:error, {:encoding_exception, _}} = Yex.Snapshot.decode_v1(<<0x80>>)
  """
  @spec decode_v1(binary()) :: {:ok, t()} | {:error, {:encoding_exception, String.t()}}
  def decode_v1(bytes) when is_binary(bytes), do: Yex.Nif.snapshot_decode_v1(bytes)

  @doc """
  Decodes a snapshot encoded in lib0 v2 format (yjs `encodeSnapshotV2`).

  The returned snapshot is not bound to a document (`doc: nil`).
  """
  @spec decode_v2(binary()) :: {:ok, t()} | {:error, {:encoding_exception, String.t()}}
  def decode_v2(bytes) when is_binary(bytes), do: Yex.Nif.snapshot_decode_v2(bytes)

  @doc """
  Returns true when both snapshots have the same state vector and delete set, like yjs
  `equalSnapshots`. The document a snapshot came from is ignored.

  Delete sets are compared after merging adjacent ranges, so two encodings of the same
  set compare equal even when yjs, which compares the raw range lists, would not.

  ## Examples
      iex> {:ok, a} = Yex.Snapshot.decode_v1(<<1, 1, 2, 1, 1, 2, 1, 0>>)
      iex> {:ok, b} = Yex.Snapshot.decode_v1(<<1, 1, 1, 1, 2, 0>>)
      iex> Yex.Snapshot.equal?(a, b)
      true
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{} = a, %__MODULE__{} = b), do: encode_v1(a) == encode_v1(b)

  @doc """
  Encodes the state of the snapshot's document as of the snapshot, in lib0 v1 format.

  Raises `ArgumentError` for a decoded snapshot; use `encode_state_v1/2` instead.
  """
  @spec encode_state_v1(t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v1(%__MODULE__{} = snapshot),
    do: encode_state_v1(snapshot, bound_doc(snapshot))

  @doc """
  Encodes the state of `doc` as of `snapshot`, in lib0 v1 format.

  `snapshot` can come from any replica of the document, for example a decoded one.
  Returns `{:error, {:encoding_exception, _}}` when `doc` has garbage collection enabled.

  A client whose first updates `doc` has not received (yrs integrates its later ones
  behind a gap) is left out of the result.
  """
  @spec encode_state_v1(t(), Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v1(%__MODULE__{reference: reference}, %Yex.Doc{} = doc) do
    Doc.run_in_worker_process doc do
      Yex.Nif.transaction_encode_state_from_snapshot_v1(doc, cur_txn(doc), reference)
    end
  end

  @doc """
  Encodes the state of the snapshot's document as of the snapshot, in lib0 v2 format.

  Raises `ArgumentError` for a decoded snapshot; use `encode_state_v2/2` instead.
  """
  @spec encode_state_v2(t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v2(%__MODULE__{} = snapshot),
    do: encode_state_v2(snapshot, bound_doc(snapshot))

  @doc """
  Encodes the state of `doc` as of `snapshot`, in lib0 v2 format.

  `snapshot` can come from any replica of the document, for example a decoded one.
  Returns `{:error, {:encoding_exception, _}}` when `doc` has garbage collection enabled.

  A client whose first updates `doc` has not received (yrs integrates its later ones
  behind a gap) is left out of the result.
  """
  @spec encode_state_v2(t(), Yex.Doc.t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v2(%__MODULE__{reference: reference}, %Yex.Doc{} = doc) do
    Doc.run_in_worker_process doc do
      Yex.Nif.transaction_encode_state_from_snapshot_v2(doc, cur_txn(doc), reference)
    end
  end

  @doc """
  Restores `origin_doc` as of `snapshot` into `target`, like yjs `createDocFromSnapshot`.

  `target` defaults to a new document, owned by the calling process and created after the
  snapshot is read. Returns `{:error, {:encoding_exception, _}}` when `origin_doc` has
  garbage collection enabled, like `encode_state_v2/2`, and `{:error, reason}` when
  applying the update to `target` fails.

  ## Examples
      iex> doc = Yex.Doc.with_options(%Yex.Doc.Options{skip_gc: true})
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "world!")
      iex> {:ok, snapshot} = Yex.snapshot(doc)
      iex> Yex.Text.insert(text, 0, "hello ")
      iex> {:ok, restored} = Yex.Snapshot.create_doc(snapshot, doc)
      iex> Yex.Doc.get_text(restored, "text") |> Yex.Text.to_string()
      "world!"
  """
  @spec create_doc(t(), Yex.Doc.t(), Yex.Doc.t() | nil) :: {:ok, Yex.Doc.t()} | {:error, term()}
  def create_doc(%__MODULE__{} = snapshot, %Yex.Doc{} = origin_doc, target \\ nil) do
    with {:ok, update} <- encode_state_v2(snapshot, origin_doc),
         target = target || Doc.new(),
         :ok <- Yex.apply_update_v2(target, update),
         do: {:ok, target}
  end

  @doc false
  # Shared body of Yex.Text.to_delta/3 and Yex.XmlText.to_delta/3.
  def to_delta(%{doc: doc} = shared, nif, snapshot, prev_snapshot) do
    Doc.run_in_worker_process doc do
      nif.(shared, cur_txn(shared), reference(snapshot), reference(prev_snapshot))
    end
  end

  defp reference(nil), do: nil
  defp reference(%__MODULE__{reference: reference}), do: reference

  defp bound_doc(%__MODULE__{doc: %Yex.Doc{} = doc}), do: doc

  defp bound_doc(%__MODULE__{doc: nil}) do
    raise ArgumentError,
          "snapshot is not bound to a document; pass the document as the second argument"
  end
end
