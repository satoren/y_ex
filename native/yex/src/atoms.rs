rustler::atoms! {
    ok,
    error,
    terminated,
    poison_error,
    transaction_acq_error,
    encoding_exception,
    update_v1,
    update_v2,

    observe_event,
    observe_deep_event,

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
}
