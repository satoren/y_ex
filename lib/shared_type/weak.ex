defmodule Yex.WeakLink do
  @moduledoc """
  ### ⚠️ Experimental

  A weak link to a value in a shared map.
  """

  alias Yex.Doc
  require Yex.Doc

  defstruct [
    :doc,
    :reference
  ]

  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }
  def to_string(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_string(weak, cur_txn(weak))
    end
  end

  def to_list(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_unquote(weak, cur_txn(weak))
    end
  end

  def deref(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_deref(weak, cur_txn(weak))
    end
  end

  @doc """
  Converts the weak link to its preliminary representation.
  """
  @spec as_prelim(t) :: Yex.WeakPrelim.t()
  def as_prelim(%__MODULE__{doc: doc} = weak_link) do
    Doc.run_in_worker_process(doc,
      do:
        Yex.Array.to_list(weak_link)
        |> Enum.map(&Yex.Output.as_prelim/1)
        |> Yex.ArrayPrelim.from()
    )
  end

  defimpl Yex.Output do
    def as_prelim(array) do
      Yex.WeakLink.as_prelim(array)
    end
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end
end

defmodule Yex.WeakPrelim do
  @moduledoc """
  ### ⚠️ Experimental

  A preliminary weak link to a value.

  This Prelim type contains native resources,
  so it cannot be serialized or deserialized for now.
  """

  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: reference()
        }
end
