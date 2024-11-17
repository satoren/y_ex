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
    let arc = ResourceArc::new(resource);
    
    let arc_clone = arc.clone();
    let _ = doc.reference.doc.observe_update_v2(move |_txn, _e| {
        if let Ok(_manager) = arc_clone.0.write() {
            // The UndoManager will track changes automatically
            // when they're made with the correct origin
        }
    });
    
    NifUndoManager {
        reference: arc,
    }
}

#[rustler::nif]
pub fn undo_manager_include_origin(undo_manager: NifUndoManager, origin: Binary) {
    let origin = Origin::from(origin.as_slice());
    undo_manager.reference.0.write().unwrap().include_origin(origin);
}

#[rustler::nif]
pub fn undo_manager_undo(undo_manager: NifUndoManager) -> bool {
    let mut manager = undo_manager.reference.0.write().unwrap();
    match manager.try_undo() {
        Ok(did_undo) => {
            println!("Undo result: {}", did_undo);
            did_undo
        },
        Err(e) => {
            println!("Undo error: {:?}", e);
            false
        }
    }
}


