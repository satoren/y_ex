defmodule Yex.Text do
  @moduledoc """
  A shareable type that is optimized for shared editing on text.
  """
  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  def insert(%__MODULE__{} = text, index, content) do
    Yex.Nif.text_insert(text, index, content)
  end

  def insert(%__MODULE__{} = text, index, content, attr) do
    Yex.Nif.text_insert_with_attributes(text, index, content, attr)
  end

  def delete(%__MODULE__{} = text, index, length) do
    Yex.Nif.text_delete(text, index, length)
  end

  def format(%__MODULE__{} = text, index, length, attr) do
    Yex.Nif.text_format(text, index, length, attr)
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> delta = [%{ "retain" => 1}, %{ "delete" => 3}]
      iex> Yex.Text.insert(text,0, "12345")
      iex> Yex.Text.apply_delta(text,delta)
      iex> Yex.Text.to_delta(text)
      [%{"insert" => "15"}]
  """
  def apply_delta(%__MODULE__{} = text, delta) do
    Yex.Nif.text_apply_delta(text, delta)
  end

  def to_string(%__MODULE__{} = text) do
    Yex.Nif.text_to_string(text)
  end

  def length(%__MODULE__{} = text) do
    Yex.Nif.text_length(text)
  end

  def to_json(%__MODULE__{} = _text) do
    raise "Not implemented"
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples Sync two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "12345")
      iex> Yex.Text.insert(text, 0, "0", %{"bold" => true})
      iex> Yex.Text.to_delta(text)
      [%{"insert" => "0", "attributes" => %{"bold" => true}}, %{"insert" => "12345"}]
  """
  def to_delta(%__MODULE__{} = text) do
    Yex.Nif.text_to_delta(text)
  end
end
