use yrs::UndoManager;
use rustler::{Env, ResourceArc, NifStruct};
use std::sync::RwLock;
use crate::{
    text::NifText,
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
pub fn undo_manager_new(env: Env<'_>, doc: NifDoc, scope: NifText) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        std::eprintln!("DEBUG: undo_manager_new starting");
        let branch = scope.readonly(None, |txn| {
            std::eprintln!("DEBUG: getting branch reference");
            scope.get_ref(txn)
        })?;
        std::eprintln!("DEBUG: branch obtained: {:?}", branch);
        
        let undo_manager = UndoManager::new(&doc, &branch);
        std::eprintln!("DEBUG: UndoManager created");
        
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
        std::eprintln!("DEBUG: include_origin starting");
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(origin) = term_to_origin_binary(origin_term) {
            std::eprintln!("DEBUG: including origin (length: {})", origin.len());
            manager.include_origin(origin.as_slice());
            std::eprintln!("DEBUG: origin included");
        } else {
            std::eprintln!("DEBUG: no origin to include");
        }
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        std::eprintln!("DEBUG: undo_manager_undo starting");
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if !manager.can_undo() {
            std::eprintln!("DEBUG: nothing to undo");
            return Ok(());
        }
        
        let stack = manager.undo_stack();
        std::eprintln!("DEBUG: undo stack length: {}", stack.len());
        for (i, item) in stack.iter().enumerate() {
            std::eprintln!("DEBUG: stack item {}: {:?}", i, item);
        }
        
        manager.undo_blocking();
        std::eprintln!("DEBUG: undo operation completed");
        
        Ok(())
    })
}


