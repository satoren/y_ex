defmodule Yex.WeakLink do
  @moduledoc """
  ### ⚠️ Experimental

  A weak link to a value in a shared map.

  **Type Safety Note:** WeakLink does not store runtime type information.
  Callers must use the correct method based on the original source type:
  - `to_string/1` for Text/XMLText quotes
  - `to_list/1` for Array quotes
  - `deref/1` for Map links

  Calling the wrong method may result in undefined behavior or panics.
  """

  alias Yex.Doc
  require Yex.Doc

  defstruct [
    :doc,
    :reference
  ]

  @doc """
  Converts the (Text/XMLText) weak link to its string representation.
  """
  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @spec to_string(Yex.WeakLink.t()) :: String.t()
  def to_string(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_string(weak, cur_txn(weak))
    end
  end

  @doc """
  Converts the (Array) weak link to a list of its elements.
  """
  @spec to_list(t()) :: list()
  def to_list(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_unquote(weak, cur_txn(weak))
    end
  end

  @doc """
  Dereferences the (Map) weak link to obtain the actual value it points to.
  """
  @spec deref(t()) :: any()
  def deref(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process doc do
      Yex.Nif.weak_deref(weak, cur_txn(weak))
    end
  end

  @doc """
  Converts the weak link to its preliminary representation.
  """
  @spec as_prelim(t()) :: Yex.WeakPrelim.t()
  def as_prelim(%Yex.WeakLink{doc: doc} = weak) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.weak_as_prelim(weak, cur_txn(weak))
    )
  end

  defimpl Yex.Output do
    def as_prelim(weak_link) do
      Yex.WeakLink.as_prelim(weak_link)
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
