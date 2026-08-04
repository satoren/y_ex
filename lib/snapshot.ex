defmodule Yex.Snapshot do
  @moduledoc """
  Opaque snapshot of a document state at a specific point in time.

  Use `Yex.snapshot/1` to create it and `encode_state_v1/1`
  or `encode_state_v2/1` to generate time-travel updates.
  """

  alias Yex.Doc
  require Yex.Doc

  defstruct [:doc, :reference]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: binary()
        }

  @doc """
  Encodes document state represented by this snapshot in lib0 v1 format.
  """
  @spec encode_state_v1(t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v1(%__MODULE__{doc: %Yex.Doc{} = doc} = snapshot) do
    Doc.run_in_worker_process doc do
      Yex.Nif.transaction_encode_state_from_snapshot_v1(cur_txn(doc), snapshot)
    end
  end

  @doc """
  Encodes document state represented by this snapshot in lib0 v2 format.
  """
  @spec encode_state_v2(t()) :: {:ok, binary()} | {:error, term()}
  def encode_state_v2(%__MODULE__{doc: %Yex.Doc{} = doc} = snapshot) do
    Doc.run_in_worker_process doc do
      Yex.Nif.transaction_encode_state_from_snapshot_v2(cur_txn(doc), snapshot)
    end
  end

  defp cur_txn(%Yex.Doc{reference: doc_ref}) do
    Process.get(doc_ref, nil)
  end
end
