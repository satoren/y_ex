defmodule Yex.DeletedSharedTypeError do
  @moduledoc """
  Raised when an operation is performed on a shared type that has been deleted
  from its document, for example a nested type removed from its parent.
  """
  defexception message: "Shared type has been deleted"
end

defmodule Yex.TransactionAcqError do
  @moduledoc """
  Raised when a transaction on a document cannot be acquired because another
  transaction is already open, for example inside `Yex.Doc.transaction/3` or
  while another process holds one.
  """
  defexception message: "Failed to acquire transaction: another transaction is in progress"
end
