mod any;
mod array;
mod atoms;
mod awareness;
mod doc;
mod error;
mod map;
mod shared_type;
mod subscription;
mod sync;
mod term_box;
mod text;
mod utils;
mod wrap;
mod xml;
mod yinput;
mod youtput;
mod undo;

use any::NifAny;
use array::NifArray;
use doc::{DocResource, NifDoc};
use error::NifError;
use map::NifMap;
use rustler::{Env, NifStruct, ResourceArc};
use scoped_thread_local::scoped_thread_local;
use text::NifText;
+use undo::NifUndoManager;

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
}

#[derive(NifStruct)]
#[module = "Yex.WeakLink"]
pub struct NifWeakLink {
    // not supported yet
    doc: ResourceArc<DocResource>,
}

#[derive(NifStruct)]
#[module = "Yex.UndefinedRef"]
pub struct NifUndefinedRef {
    // not supported yet or...?
    doc: ResourceArc<DocResource>,
}

rustler::init!(
    "Elixir.Yex.Nif",
    [
        // Doc operations
        doc::doc_new,
        doc::doc_with_options,
        doc::doc_get_or_insert_text,
        doc::doc_get_or_insert_array,
        doc::doc_get_or_insert_map,
        doc::doc_get_or_insert_xml_fragment,
        doc::doc_monitor_update_v1,
        doc::doc_monitor_update_v2,
        doc::doc_begin_transaction,
        
        // Subscription
        subscription::sub_unsubscribe,
        
        // Transaction
        doc::commit_transaction,
        
        // Text operations
        text::text_insert,
        text::text_insert_with_attributes,
        text::text_apply_delta,
        text::text_to_delta,
        text::text_delete,
        text::text_format,
        text::text_to_string,
        text::text_length,
        
        // Array operations
        array::array_insert,
        array::array_insert_list,
        array::array_length,
        array::array_to_list,
        array::array_get,
        array::array_delete_range,
        array::array_to_json,
        
        // Map operations
        map::map_set,
        map::map_size,
        map::map_get,
        map::map_delete,
        map::map_to_map,
        map::map_to_json,
        
        // XML Fragment operations
        xml::xml_fragment_insert,
        xml::xml_fragment_delete_range,
        xml::xml_fragment_get,
        xml::xml_fragment_to_string,
        xml::xml_fragment_length,
        xml::xml_fragment_parent,
        
        // XML Element operations
        xml::xml_element_insert,
        xml::xml_element_delete_range,
        xml::xml_element_get,
        xml::xml_element_length,
        xml::xml_element_insert_attribute,
        xml::xml_element_remove_attribute,
        xml::xml_element_get_attribute,
        xml::xml_element_get_attributes,
        xml::xml_element_next_sibling,
        xml::xml_element_prev_sibling,
        xml::xml_element_to_string,
        xml::xml_element_parent,
        
        // XML Text operations
        xml::xml_text_insert,
        xml::xml_text_insert_with_attributes,
        xml::xml_text_delete,
        xml::xml_text_format,
        xml::xml_text_apply_delta,
        xml::xml_text_length,
        xml::xml_text_next_sibling,
        xml::xml_text_prev_sibling,
        xml::xml_text_to_delta,
        xml::xml_text_to_string,
        xml::xml_text_parent,
        
        // State and Update operations
        doc::encode_state_vector_v1,
        doc::encode_state_as_update_v1,
        doc::apply_update_v1,
        doc::encode_state_vector_v2,
        doc::encode_state_as_update_v2,
        doc::apply_update_v2,
        
        // Sync operations
        sync::sync_message_decode_v1,
        sync::sync_message_encode_v1,
        sync::sync_message_decode_v2,
        sync::sync_message_encode_v2,
        
        // Awareness operations
        awareness::awareness_new,
        awareness::awareness_client_id,
        awareness::awareness_get_client_ids,
        awareness::awareness_get_states,
        awareness::awareness_get_local_state,
        awareness::awareness_set_local_state,
        awareness::awareness_clean_local_state,
        awareness::awareness_monitor_update,
        awareness::awareness_monitor_change,
        awareness::awareness_encode_update_v1,
        awareness::awareness_apply_update_v1,
        awareness::awareness_remove_states,
        
        // Undo Manager operations
        undo::undo_manager_new,
        undo::undo_manager_undo,
        undo::undo_manager_redo,
        undo::undo_manager_can_undo,
        undo::undo_manager_can_redo,
        undo::undo_manager_clear,
        undo::undo_manager_add_tracked_origin,
        undo::undo_manager_remove_tracked_origin
    ]
);
