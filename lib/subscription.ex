defmodule Yex.Subscription do
  @moduledoc """
  A subscription .
  """
  defstruct [
    :reference,
    :doc
  ]

  alias Yex.Doc
  require Yex.Doc

  @type t :: %__MODULE__{
          reference: reference(),
          doc: Yex.Doc.t()
        }

  def register(%__MODULE__{} = sub, ref \\ make_ref()) do
    # Subscription should not be automatically released by gc, so put it in the process dictionary
    Process.put(ref, sub)
    ref
  end

  def unsubscribe(ref) do
    case Process.get(ref) do
      %__MODULE__{doc: doc} = sub ->
        Process.delete(ref)

        Doc.run_in_worker_process doc do
          Yex.Nif.sub_unsubscribe(sub)
        end

      _ ->
        :ok
    end
  end
end
