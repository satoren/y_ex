defmodule Yex.Doc do
  defmodule Options do
    defstruct client_id: 0,
              guid: nil,
              collection_id: nil,
              offset_kind: :bytes,
              skip_gc: false,
              auto_load: false,
              should_load: true
  end

  defstruct [
    :reference
  ]

  @type t :: %__MODULE__{
          reference: any()
        }

  def new() do
    Yex.Nif.doc_new()
  end

  def with_options(%Options{} = option) do
    Yex.Nif.doc_with_options(option)
  end

  def get_text(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_text(doc, name)
  end

  def get_array(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_array(doc, name)
  end

  def get_map(%__MODULE__{} = doc, name) do
    Yex.Nif.doc_get_or_insert_map(doc, name)
  end

  def get_xml_fragment(%__MODULE__{} = doc, name) do
    raise "Not implemented"
    Yex.Nif.doc_get_or_insert_xml_fragment(doc, name)
  end

  def transaction(%__MODULE__{} = doc, exec) do
    case Yex.Nif.doc_begin_transaction(doc, nil) do
      {:ok, _} ->
        exec.()
        Yex.Nif.doc_commit_transaction(doc)
        :ok

      error ->
        error
    end
  end

  def transaction(%__MODULE__{} = doc, origin, exec) do
    case Yex.Nif.doc_begin_transaction(doc, origin) do
      {:ok, _} ->
        exec.()
        Yex.Nif.doc_commit_transaction(doc)
        :ok

      error ->
        error
    end
  end

  def monitor_update_v1(%__MODULE__{} = doc) do
    Yex.Nif.doc_monitor_update_v1(doc, self())
  end

  #  def monitor_update_v2(%__MODULE__{} = doc) do
  #    Yex.Nif.doc_monitor_update_v2(doc, self())
  #  end

  def demonitor_update_v1(sub) do
    Yex.Nif.sub_unsubscribe(sub)
  end

  #  def demonitor_update_v2(sub) do
  #    Yex.Nif.sub_unsubscribe(sub)
  #  end
end
