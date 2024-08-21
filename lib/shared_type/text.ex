defmodule Yex.Text do
  @moduledoc """
  A shareable type that is optimized for shared editing on text.
  """
  defstruct [
    :reference
  ]

  @type delta ::
          [%{:insert => Yex.input_type(), optional(:attributes) => map()}]
          | [%{delete: integer()}]
          | [%{:retain => integer(), optional(:attributes) => map()}]
  @type t :: %__MODULE__{
          reference: any()
        }

  @spec insert(t, integer(), Yex.input_type()) :: :ok | :error
  def insert(%__MODULE__{} = text, index, content) do
    Yex.Nif.text_insert(text, index, content)
  end

  @spec insert(t, integer(), Yex.input_type(), map()) :: :ok | :error
  def insert(%__MODULE__{} = text, index, content, attr) do
    Yex.Nif.text_insert_with_attributes(text, index, content, attr)
  end

  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{} = text, index, length) do
    index = if index < 0, do: __MODULE__.length(text) + index, else: index
    Yex.Nif.text_delete(text, index, length) |> Yex.Nif.Util.unwrap_ok_tuple()
  end

  @spec format(t, integer(), integer(), map()) :: :ok | :error
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
      [%{insert: "15"}]
  """
  @spec apply_delta(t, delta) :: :ok | :error
  def apply_delta(%__MODULE__{} = text, delta) do
    Yex.Nif.text_apply_delta(text, delta)
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{} = text) do
    Yex.Nif.text_to_string(text)
  end

  @spec length(t) :: integer()
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
      [%{insert: "0", attributes: %{"bold" => true}}, %{insert: "12345"}]
  """
  def to_delta(%__MODULE__{} = text) do
    Yex.Nif.text_to_delta(text)
  end
end

defmodule Yex.TextPrelim do
  @moduledoc """
  A preliminary text. It can be used to early initialize the contents of a Text.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from("Hello World"))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.get(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello World"}]

  """
  defstruct [
    :delta
  ]

  @type t :: %__MODULE__{
          delta: Yex.Text.delta()
        }

  @doc """
  Transforms a Text to a TextPrelim
  ## Examples with a binary
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from("Hello World"))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.get(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello World"}]


  ## Examples with delta
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from([%{insert: "Hello"},%{insert: " World", attributes: %{ "bold" => true }},]))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.get(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello"}, %{attributes: %{"bold" => true}, insert: " World"}]
  """
  @spec from(binary()) :: t
  def from(text) when is_binary(text) do
    %__MODULE__{delta: [%{insert: text}]}
  end

  @spec from(Yex.Text.delta()) :: t
  def from(delta) do
    %__MODULE__{delta: delta}
  end
end
