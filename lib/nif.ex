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
  def doc_monitor_update_v1(_doc, _pid, _metadata), do: :erlang.nif_error(:nif_not_loaded)
  def doc_monitor_update_v2(_doc, _pid, _metadata), do: :erlang.nif_error(:nif_not_loaded)

  def sub_unsubscribe(_sub), do: :erlang.nif_error(:nif_not_loaded)

  def doc_begin_transaction(_doc, _origin), do: :erlang.nif_error(:nif_not_loaded)
  def commit_transaction(_doc), do: :erlang.nif_error(:nif_not_loaded)

  def text_insert(_text, _cur_txn, _index, _content), do: :erlang.nif_error(:nif_not_loaded)

  def text_insert_with_attributes(_text, _cur_txn, _index, _content, _attr),
    do: :erlang.nif_error(:nif_not_loaded)

  def text_apply_delta(_text, _cur_txn, _delta),
    do: :erlang.nif_error(:nif_not_loaded)

  def text_to_delta(_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def text_delete(_text, _cur_txn, _index, _len), do: :erlang.nif_error(:nif_not_loaded)
  def text_format(_text, _cur_txn, _index, _len, _attr), do: :erlang.nif_error(:nif_not_loaded)
  def text_to_string(_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def text_length(_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def array_insert(_array, _cur_txn, _index, _value), do: :erlang.nif_error(:nif_not_loaded)
  def array_insert_list(_array, _cur_txn, _index, _values), do: :erlang.nif_error(:nif_not_loaded)
  def array_length(_array, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def array_to_list(_array, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def array_get(_array, _cur_txn, _index), do: :erlang.nif_error(:nif_not_loaded)

  def array_delete_range(_array, _cur_txn, _index, _length),
    do: :erlang.nif_error(:nif_not_loaded)

  def array_move_to(_array, _cur_txn, _from, _to), do: :erlang.nif_error(:nif_not_loaded)

  def array_to_json(_array, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def map_set(_map, _cur_txn, _key, _value), do: :erlang.nif_error(:nif_not_loaded)
  def map_size(_map, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def map_get(_map, _cur_txn, _key), do: :erlang.nif_error(:nif_not_loaded)
  def map_delete(_map, _cur_txn, _key), do: :erlang.nif_error(:nif_not_loaded)
  def map_to_map(_map, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def map_to_json(_map, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_fragment_insert(_xml_fragment, _cur_txn, _index, _content),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_fragment_delete_range(_xml_fragment, _cur_txn, _index, _length),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_fragment_get(_xml_fragment, _cur_txn, _index), do: :erlang.nif_error(:nif_not_loaded)
  #  def xml_fragment_to_json(_xml_fragment, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_fragment_to_string(_xml_fragment, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_fragment_length(_xml_fragment, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_fragment_parent(_xml_fragment, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_insert(_xml_element, _cur_txn, _index, _content),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_delete_range(_xml_element, _cur_txn, _index, _length),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_get(_xml_element, _cur_txn, _index), do: :erlang.nif_error(:nif_not_loaded)
  #  def xml_element_to_json(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_element_length(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_insert_attribute(_xml_element, _cur_txn, _key, _value),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_remove_attribute(_xml_element, _cur_txn, _key),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_get_attribute(_xml_element, _cur_txn, _key),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_get_attributes(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_element_next_sibling(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_element_prev_sibling(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_element_to_string(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_element_parent(_xml_element, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_insert(_xml_text, _cur_txn, _index, _content),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_insert_with_attributes(_xml_text, _cur_txn, _index, _content, _attr),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_delete(_xml_text, _cur_txn, _index, _length),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_format(_xml_text, _cur_txn, _index, _length, _attr),
    do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_apply_delta(_xml_text, _cur_txn, _delta), do: :erlang.nif_error(:nif_not_loaded)
  def xml_text_length(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_next_sibling(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_text_prev_sibling(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_text_to_delta(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def xml_text_to_string(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def xml_text_parent(_xml_text, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)

  def encode_state_vector_v1(_doc, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def encode_state_as_update_v1(_doc, _cur_txn, _diff), do: :erlang.nif_error(:nif_not_loaded)
  def apply_update_v1(_doc, _cur_txn, _update), do: :erlang.nif_error(:nif_not_loaded)

  def encode_state_vector_v2(_doc, _cur_txn), do: :erlang.nif_error(:nif_not_loaded)
  def encode_state_as_update_v2(_doc, _cur_txn, _diff), do: :erlang.nif_error(:nif_not_loaded)
  def apply_update_v2(_doc, _cur_txn, _update), do: :erlang.nif_error(:nif_not_loaded)

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

  def awareness_monitor_update(_awareness, _pid, _metadata),
    do: :erlang.nif_error(:nif_not_loaded)

  def awareness_monitor_change(_awareness, _pid, _metadata),
    do: :erlang.nif_error(:nif_not_loaded)

  def awareness_encode_update_v1(_awareness, _clients), do: :erlang.nif_error(:nif_not_loaded)

  def awareness_apply_update_v1(_awareness, _update, _origin),
    do: :erlang.nif_error(:nif_not_loaded)

  def awareness_remove_states(_awareness, _clients), do: :erlang.nif_error(:nif_not_loaded)

  def undo_manager_new(_doc), do: :erlang.nif_error(:nif_not_loaded)
  def undo_manager_include_origin(_undo_manager, _origin), do: :erlang.nif_error(:nif_not_loaded)
  def undo_manager_undo(_undo_manager), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule Yex.Nif.Util do
  @moduledoc false
  def unwrap_ok_tuple({:ok, {}}), do: :ok
  def unwrap_ok_tuple(other), do: other
end
