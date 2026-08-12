# TODO: Feature Gaps vs yffi

## High Priority

- [x] Add update-binary debug APIs (yupdate_debug_v1 / yupdate_debug_v2)
- [x] Add APIs to retrieve pending update/pending delete set (ytransaction_pending_update / ytransaction_pending_ds / ypending_update_destroy / ydelete_set_destroy)
- [x] Add snapshot and time-travel APIs (ytransaction_snapshot / ytransaction_encode_state_from_snapshot_v1 / ytransaction_encode_state_from_snapshot_v2)
- [ ] Add UndoManager observability and stack-metrics APIs (yundo_manager_observe_added / yundo_manager_observe_popped / yundo_manager_undo_stack_len / yundo_manager_redo_stack_len)
- [ ] Add low-level Doc/Transaction control APIs (ydoc_read_transaction / ytransaction_writeable / ytransaction_force_gc / ydoc_load / ydoc_clear / ydoc_clone)

## Medium Priority

- [x] Add JSONPath query APIs (ytransaction_json_path / yjson_path_iter_next / yjson_path_iter_destroy)
- [ ] Add branch identification/re-resolution/liveness APIs (ybranch_id / ybranch_get / ybranch_alive / ybranch_json / ytype_get / ytype_kind)
- [x] Add StickyIndex serialization APIs (ysticky_index_encode / ysticky_index_decode / ysticky_index_to_json / ysticky_index_from_json / ysticky_index_assoc)
- [ ] Add low-level XML traversal APIs (yxmlelem_tree_walker / yxmlelem_tree_walker_next / yxmlelem_tree_walker_destroy)
- [ ] Add XML attribute-iterator APIs (yxmlelem_attr_iter / yxmltext_attr_iter / yxmlattr_iter_next / yxmlattr_destroy)
- [ ] Add direct XmlText attribute APIs (yxmltext_insert_attr / yxmltext_remove_attr / yxmltext_get_attr)
- [x] Add embed-specific APIs for Text/XmlText (ytext_insert_embed / yxmltext_insert_embed)
- [ ] Add detailed WeakLink read APIs (yweak_read / yweak_xml_string)

## Low Priority

- [ ] Add low-level iterator APIs for Array/Map (yarray_iter* / ymap_iter*)
- [ ] Add direct C-ABI APIs for YInput/YOutput (yinput_* / youtput_read_* / youtput_destroy)
- [ ] Add supporting APIs (ytext_chunks / ychunks_destroy / ymap_remove_all / ydoc_observe_after_transaction)
