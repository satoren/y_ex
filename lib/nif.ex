defmodule Yex.Nif do
  @moduledoc false
  # Do not use directly

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :y_ex,
    crate: "yex",
    base_url: "https://github.com/satoren/y_ex/releases/download/v#{version}",
    force_build: System.get_env("RUSTLER_PRECOMPILATION_YEX_BUILD") in ["1", "true"],
    version: version

  def doc_new(), do: :erlang.nif_error(:nif_not_loaded)
  def doc_with_options(_option), do: :erlang.nif_error(:nif_not_loaded)
  def doc_get_or_insert_text(_doc, _name), do: :erlang.nif_error(:nif_not_loaded)
  def doc_get_or_insert_array(_doc, _name), do: :erlang.nif_error(:nif_not_loaded)
  def doc_get_or_insert_map(_doc, _name), do: :erlang.nif_error(:nif_not_loaded)
  def doc_get_or_insert_xml_fragment(_doc, _name), do: :erlang.nif_error(:nif_not_loaded)
  def doc_monitor_update_v1(_doc, _pid), do: :erlang.nif_error(:nif_not_loaded)
  def doc_monitor_update_v2(_doc, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def sub_unsubscribe(_sub), do: :erlang.nif_error(:nif_not_loaded)

  def doc_begin_transaction(_doc, _origin), do: :erlang.nif_error(:nif_not_loaded)
  def doc_commit_transaction(_doc), do: :erlang.nif_error(:nif_not_loaded)

  def text_insert(_text, _index, _content), do: :erlang.nif_error(:nif_not_loaded)

  def text_insert_with_attributes(_text, _index, _content, _attr),
    do: :erlang.nif_error(:nif_not_loaded)

  def text_delete(_text, _index, _len), do: :erlang.nif_error(:nif_not_loaded)
  def text_format(_text, _index, _len, _attr), do: :erlang.nif_error(:nif_not_loaded)
  def text_to_string(_text), do: :erlang.nif_error(:nif_not_loaded)
  def text_length(_text), do: :erlang.nif_error(:nif_not_loaded)

  def array_insert(_array, _index, _value), do: :erlang.nif_error(:nif_not_loaded)
  def array_length(_array), do: :erlang.nif_error(:nif_not_loaded)
  def array_to_list(_array), do: :erlang.nif_error(:nif_not_loaded)
  def array_get(_array, _index), do: :erlang.nif_error(:nif_not_loaded)
  def array_delete_range(_array, _index, _length), do: :erlang.nif_error(:nif_not_loaded)
  def array_to_json(_array), do: :erlang.nif_error(:nif_not_loaded)

  def map_set(_map, _key, _value), do: :erlang.nif_error(:nif_not_loaded)
  def map_size(_map), do: :erlang.nif_error(:nif_not_loaded)
  def map_get(_map, _key), do: :erlang.nif_error(:nif_not_loaded)
  def map_delete(_map, _key), do: :erlang.nif_error(:nif_not_loaded)
  def map_to_map(_map), do: :erlang.nif_error(:nif_not_loaded)
  def map_to_json(_map), do: :erlang.nif_error(:nif_not_loaded)

  def encode_state_vector_v1(_doc), do: :erlang.nif_error(:nif_not_loaded)
  def encode_state_as_update_v1(_doc, _diff), do: :erlang.nif_error(:nif_not_loaded)
  def apply_update_v1(_doc, _update), do: :erlang.nif_error(:nif_not_loaded)

  def encode_state_vector_v2(_doc), do: :erlang.nif_error(:nif_not_loaded)
  def encode_state_as_update_v2(_doc, _diff), do: :erlang.nif_error(:nif_not_loaded)
  def apply_update_v2(_doc, _update), do: :erlang.nif_error(:nif_not_loaded)

  def sync_message_decode_v1(_message), do: :erlang.nif_error(:nif_not_loaded)
  def sync_message_encode_v1(_message), do: :erlang.nif_error(:nif_not_loaded)
  def sync_message_decode_v2(_message), do: :erlang.nif_error(:nif_not_loaded)
  def sync_message_encode_v2(_message), do: :erlang.nif_error(:nif_not_loaded)

  def awareness_new(_doc), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_client_id(_awareness), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_get_client_ids(_awareness), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_get_states(_awareness), do: :erlang.nif_error(:nif_not_loaded)

  def awareness_get_local_state(_awareness), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_set_local_state(_awareness, _map), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_clean_local_state(_awareness), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_monitor_update(_awareness, _pid), do: :erlang.nif_error(:nif_not_loaded)
  def awareness_monitor_change(_awareness, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def awareness_encode_update_v1(_awareness, _clients), do: :erlang.nif_error(:nif_not_loaded)

  def awareness_apply_update_v1(_awareness, _update, _origin),
    do: :erlang.nif_error(:nif_not_loaded)

  def awareness_remove_states(_awareness, _clients), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule Yex.Nif.Util do
  @moduledoc false
  def unwrap_ok_tuple({:ok, {}}), do: :ok
  def unwrap_ok_tuple(other), do: other
end
