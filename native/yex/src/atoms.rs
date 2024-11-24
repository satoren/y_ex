rustler::atoms! {
    ok,
    error,
    terminated,
    poison_error,
    transaction_acq_error,
    encoding_exception,
    update_v1,
    update_v2,



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

  insert,
  delete,
  retain,
  attributes,

  // undo message types

  // Observer events
  undo_item_added,    // for observe_item_added
  undo_item_updated,  // for observe_item_updated  
  undo_item_popped,   // for observe_item_popped

  // Event kinds
  undo,              // EventKind::Undo
  redo,              // EventKind::Redo

  // Type identifiers for branches
  text,
  map,
  array,
  xml_element,
  xml_fragment,
  xml_text,
}
