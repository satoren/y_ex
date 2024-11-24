use yrs::UndoManager;
use rustler::{Env, ResourceArc, NifStruct};
use std::sync::RwLock;
use crate::{
    text::NifText,
    array::NifArray,
    map::NifMap,
    shared_type::NifSharedType,
    wrap::NifWrap,
    NifDoc,
    utils::term_to_origin_binary,
    NifError,
    ENV,
};

pub type UndoManagerResource = NifWrap<RwLock<UndoManager>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

#[rustler::nif]
pub fn undo_manager_new_text(env: Env<'_>, doc: NifDoc, scope: NifText) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let branch = scope.readonly(None, |txn| scope.get_ref(txn))?;
        let undo_manager = UndoManager::new(&doc, &branch);
        let resource = ResourceArc::new(UndoManagerResource::from(RwLock::new(undo_manager)));
        
        Ok(NifUndoManager {
            reference: resource,
        })
    })
}

#[rustler::nif]
pub fn undo_manager_new_array(env: Env<'_>, doc: NifDoc, scope: NifArray) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let branch = scope.readonly(None, |txn| scope.get_ref(txn))?;
        let undo_manager = UndoManager::new(&doc, &branch);
        let resource = ResourceArc::new(UndoManagerResource::from(RwLock::new(undo_manager)));
        
        Ok(NifUndoManager {
            reference: resource,
        })
    })
}

#[rustler::nif]
pub fn undo_manager_new_map(env: Env<'_>, doc: NifDoc, scope: NifMap) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let branch = scope.readonly(None, |txn| scope.get_ref(txn))?;
        let undo_manager = UndoManager::new(&doc, &branch);
        let resource = ResourceArc::new(UndoManagerResource::from(RwLock::new(undo_manager)));
        
        Ok(NifUndoManager {
            reference: resource,
        })
    })
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>, 
    undo_manager: NifUndoManager, 
    origin_term: rustler::Term
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(origin) = term_to_origin_binary(origin_term) {
            manager.include_origin(origin.as_slice());
        }
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if !manager.can_undo() {
            return Ok(());
        }
        
        manager.undo_blocking();
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if !manager.can_redo() {
            return Ok(());
        }
        
        manager.redo_blocking();
        
        Ok(())
    })
}


