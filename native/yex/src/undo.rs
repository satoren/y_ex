use crate::wrap::NifWrap;
use crate::doc::NifDoc;
use rustler::{NifStruct, ResourceArc, Binary};
use yrs::{UndoManager, undo::Options, Origin};
use std::sync::RwLock;

pub type UndoManagerResource = NifWrap<RwLock<UndoManager>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

#[rustler::nif]
pub fn undo_manager_new(doc: NifDoc) -> NifUndoManager {
    let undo_manager = UndoManager::with_options(&doc.reference.doc, Options::default());
    
    let resource = UndoManagerResource::from(RwLock::new(undo_manager));
    NifUndoManager {
        reference: ResourceArc::new(resource),
    }
}

#[rustler::nif]
pub fn undo_manager_include_origin(undo_manager: NifUndoManager, origin: Binary) {
    let origin = Origin::from(origin.as_slice());
    undo_manager.reference.0.write().unwrap().include_origin(origin);
}
