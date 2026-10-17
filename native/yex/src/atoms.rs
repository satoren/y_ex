rustler::atoms! {
    ok,
    error,
  invalid_json,
    invalid_json_path,
    terminated,
    poison_error,

    encoding_exception,
    update_v1,
    update_v2,
    subdocs,

    observe_event,
    observe_deep_event,

    out_of_bounds,
    dirty,

    // root kinds
    map,
    array,
    text,
    xml_fragment,
    xml_element,
    xml_text,
    weak_link,
    // branch ids and resolve errors
    root,
    nested,
    deleted,
    untyped,
    unsupported,

// messages types
  sync,
  awareness,
  auth,
  query_awareness,
  custom,
  sync_step1,
  sync_step2,
  sync_update,

  //awareness message types
  awareness_update,
  awareness_change,

  action,
  old_value,
  new_value,
  add,
  update,
  insert,
  delete,
  retain,
  attributes,

  // undo manager stack events
  undo_manager_event,
  added,
  updated,
  popped,
  undo,
  redo,
  kind,
  item,
  origin,
  meta,
  not_found,
  struct_ = "__struct__",
  // prelim structs and their fields
  map_prelim = "Elixir.Yex.MapPrelim",
  array_prelim = "Elixir.Yex.ArrayPrelim",
  text_prelim = "Elixir.Yex.TextPrelim",
  xml_element_prelim = "Elixir.Yex.XmlElementPrelim",
  xml_fragment_prelim = "Elixir.Yex.XmlFragmentPrelim",
  xml_text_prelim = "Elixir.Yex.XmlTextPrelim",
  list,
  delta,
  tag,
  children,
  type_ = "type",
}
