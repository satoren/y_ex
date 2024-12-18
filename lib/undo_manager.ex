defmodule Yex.UndoManager.Options do
  @moduledoc """
  Options for creating an UndoManager.

  * `:capture_timeout` - Time in milliseconds to wait before creating a new capture group
  """
  # Default from Yrs
  defstruct capture_timeout: 500

  @type t :: %__MODULE__{
          capture_timeout: non_neg_integer()
        }
end

defmodule Yex.UndoManager do
  alias Yex.UndoManager.Options

  defguard is_valid_scope(scope)
           when is_struct(scope, Yex.Text) or
                  is_struct(scope, Yex.Array) or
                  is_struct(scope, Yex.Map) or
                  is_struct(scope, Yex.XmlText) or
                  is_struct(scope, Yex.XmlElement) or
                  is_struct(scope, Yex.XmlFragment)

  @moduledoc """
  Represents a Y.UndoManager instance.
  """
  defstruct [:reference]

  @type t :: %__MODULE__{
          reference: reference()
        }

  @doc """
  Creates a new UndoManager for the given document and scope with default options.
  The scope can be a Text, Array, or Map type.

  ## Errors
  - Returns `{:error, "Invalid scope: expected a struct"}` if scope is not a struct
  - Returns `{:error, "Failed to get branch reference"}` if there's an error accessing the scope
  """
  @spec new(Yex.Doc.t(), struct()) ::
          {:ok, Yex.UndoManager.t()} | {:error, term()}
  def new(doc, scope)
      when is_valid_scope(scope) do
    new_with_options(doc, scope, %Options{})
  end

  @doc """
  Creates a new UndoManager with the given options.

  ## Options

  See `Yex.UndoManager.Options` for available options.

  ## Errors
  - Returns `{:error, "NIF error: <message>"}` if underlying NIF returns an error
  """
  @spec new_with_options(Yex.Doc.t(), struct(), Options.t()) ::
          {:ok, Yex.UndoManager.t()} | {:error, term()}
  def new_with_options(doc, scope, options)
      when is_valid_scope(scope) and
             is_struct(options, Options) do
    try do
      Yex.Nif.undo_manager_new_with_options(doc, scope, options)
    rescue
      e in ArgumentError -> {:error, "NIF error: #{Exception.message(e)}"}
    end
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.
  """
  def include_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_include_origin(undo_manager, origin)
  end

  @doc """
  Excludes an origin from being tracked by the UndoManager.
  """
  def exclude_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_exclude_origin(undo_manager, origin)
  end

  @doc """
  Undoes the last tracked change.
  """
  def undo(undo_manager) do
    Yex.Nif.undo_manager_undo(undo_manager)
  end

  @doc """
  Redoes the last undone change.
  """
  def redo(undo_manager) do
    Yex.Nif.undo_manager_redo(undo_manager)
  end

  @doc """
  Expands the scope of the UndoManager to include additional shared types.
  The scope can be a Text, Array, or Map type.
  """
  def expand_scope(undo_manager, scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, scope)
  end

  @doc """
  Stops capturing changes for the current stack item.
  This ensures that the next change will create a new stack item instead of
  being merged with the previous one, even if it occurs within the normal timeout window.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "a")
      UndoManager.stop_capturing(undo_manager)
      Text.insert(text, 1, "b")
      UndoManager.undo(undo_manager)
      # Text.to_string(text) will be "a" (only "b" was removed)
  """
  def stop_capturing(undo_manager) do
    Yex.Nif.undo_manager_stop_capturing(undo_manager)
  end

  @doc """
  Clears all StackItems stored within current UndoManager, effectively resetting its state.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " World")
      UndoManager.clear(undo_manager)
      # All undo/redo history is now cleared
  """
  def clear(undo_manager) do
    Yex.Nif.undo_manager_clear(undo_manager)
  end
end
