defmodule Yex.Text do
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

  def apply_delta(%__MODULE__{} = _text, _delta) do
    # Yex.Nif.text_apply_delta(text, delta)
    raise "Not implemented"
  end

  def to_string(%__MODULE__{} = text) do
    Yex.Nif.text_to_string(text)
  end

  def length(%__MODULE__{} = text) do
    Yex.Nif.text_length(text)
  end

  def to_json(%__MODULE__{} = _text) do
    # todo: need to implement
    raise "Not implemented"
  end
end
