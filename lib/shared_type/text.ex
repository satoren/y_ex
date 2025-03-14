defmodule Yex.Text do
  @moduledoc """
  A shareable type that is optimized for shared editing on text.
  """
  defstruct [
    :doc,
    :reference
  ]

  alias Yex.Doc
  require Yex.Doc

  @type delta ::
          [%{:insert => Yex.input_type(), optional(:attributes) => map()}]
          | [%{delete: integer()}]
          | [%{:retain => integer(), optional(:attributes) => map()}]
  @type t :: %__MODULE__{
          doc: Yex.Doc.t(),
          reference: reference()
        }

  @spec insert(t, integer(), Yex.input_type()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = text, index, content) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_insert(text, cur_txn(text), index, content)
    )
  end

  @spec insert(t, integer(), Yex.input_type(), map()) :: :ok | :error
  def insert(%__MODULE__{doc: doc} = text, index, content, attr) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_insert_with_attributes(text, cur_txn(text), index, content, attr)
    )
  end

  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{doc: doc} = text, index, length) do
    Doc.run_in_worker_process doc do
      index = if index < 0, do: __MODULE__.length(text) + index, else: index
      Yex.Nif.text_delete(text, cur_txn(text), index, length)
    end
  end

  @spec format(t, integer(), integer(), map()) :: :ok | :error
  def format(%__MODULE__{doc: doc} = text, index, length, attr) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_format(text, cur_txn(text), index, length, attr)
    )
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples Syncs two clients by exchanging the complete document structure
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> delta = [%{ "retain" => 1}, %{ "delete" => 3}]
      iex> Yex.Text.insert(text,0, "12345")
      iex> Yex.Text.apply_delta(text,delta)
      iex> Yex.Text.to_delta(text)
      [%{insert: "15"}]
  """
  @spec apply_delta(t, delta) :: :ok | :error
  def apply_delta(%__MODULE__{doc: doc} = text, delta) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_apply_delta(text, cur_txn(text), delta)
    )
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_to_string(text, cur_txn(text))
    )
  end

  @spec length(t) :: integer()
  def length(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_length(text, cur_txn(text))
    )
  end

  @doc """
  Transforms this type to a Quill Delta

  ## Examples creates a few changes, then gets them back as a batch of change maps
      iex> doc = Yex.Doc.new()
      iex> text = Yex.Doc.get_text(doc, "text")
      iex> Yex.Text.insert(text, 0, "12345")
      iex> Yex.Text.insert(text, 0, "0", %{"bold" => true})
      iex> Yex.Text.to_delta(text)
      [%{insert: "0", attributes: %{"bold" => true}}, %{insert: "12345"}]
  """
  @spec to_delta(t) :: delta()
  def to_delta(%__MODULE__{doc: doc} = text) do
    Doc.run_in_worker_process(doc,
      do: Yex.Nif.text_to_delta(text, cur_txn(text))
    )
  end

  defp cur_txn(%{doc: %Yex.Doc{reference: doc_ref}}) do
    Process.get(doc_ref, nil)
  end

  @spec as_prelim(t) :: Yex.TextPrelim.t()
  def as_prelim(%__MODULE__{} = text) do
    Yex.Text.to_delta(text) |> Yex.TextPrelim.from()
  end

  defimpl Yex.Output do
    def as_prelim(text) do
      Yex.Text.as_prelim(text)
    end
  end
end

defmodule Yex.TextPrelim do
  @moduledoc """
  A preliminary text. It can be used to early initialize the contents of a Text.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from("Hello World"))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
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
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
      iex> Yex.Text.to_delta(text)
      [%{insert: "Hello World"}]


  ## Examples with delta
      iex> doc = Yex.Doc.new()
      iex> map = Yex.Doc.get_map(doc, "map")
      iex> Yex.Map.set(map, "key", Yex.TextPrelim.from([%{insert: "Hello"},%{insert: " World", attributes: %{ "bold" => true }},]))
      iex> {:ok, %Yex.Text{} = text} = Yex.Map.fetch(map, "key")
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
