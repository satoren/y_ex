use yrs::UndoManager;
use rustler::{Env, NifTaggedEnum, ResourceArc, NifStruct, Term};
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

#[derive(NifTaggedEnum)]
pub enum SharedTypeInput {
    Text(NifText),
    Array(NifArray),
    Map(NifMap),
}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: SharedTypeInput,
) -> NifUndoManager {
    ENV.set(&mut env.clone(), || {
        match scope {
            SharedTypeInput::Text(text) => create_undo_manager(env, doc, text),
            SharedTypeInput::Array(array) => create_undo_manager(env, doc, array),
            SharedTypeInput::Map(map) => create_undo_manager(env, doc, map),
        }
    })
}


pub type UndoManagerResource = NifWrap<RwLock<UndoManager>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

fn create_undo_manager<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T
) -> NifUndoManager {
    let branch = scope.readonly(None, |txn| {
        scope.get_ref(txn)
    }).unwrap();
    
    let undo_manager = UndoManager::new(&doc, &branch);
    let resource = ResourceArc::new(UndoManagerResource::from(RwLock::new(undo_manager)));
    
    NifUndoManager {
        reference: resource,
    }
}

// #[rustler::nif]
// pub fn undo_manager_new_text(env: Env<'_>, doc: NifDoc, scope: NifText) -> NifUndoManager {
//     create_undo_manager(env, doc, scope)
// }

// #[rustler::nif]
// pub fn undo_manager_new_array(env: Env<'_>, doc: NifDoc, scope: NifArray) -> NifUndoManager {
//     create_undo_manager(env, doc, scope)
// }

// #[rustler::nif]
// pub fn undo_manager_new_map(env: Env<'_>, doc: NifDoc, scope: NifMap) -> NifUndoManager {
//     create_undo_manager(env, doc, scope)
// }

fn with_write_lock_if<F>(
    undo_manager: &NifUndoManager,
    can_proceed: impl Fn(&UndoManager) -> bool,
    operation: F
) -> Result<(), NifError>
where
    F: FnOnce(&mut UndoManager)
{
    {
        let read_manager = undo_manager.reference.read()
            .map_err(|_| NifError::Message("Failed to acquire read lock".to_string()))?;
        
        if !can_proceed(&read_manager) {
            return Ok(());
        }
    }

    let mut write_manager = undo_manager.reference.write()
        .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
    
    if can_proceed(&write_manager) {
        operation(&mut write_manager);
    }
    
    Ok(())
}


#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>, 
    undo_manager: NifUndoManager, 
    origin_term: Term
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
        with_write_lock_if(
            &undo_manager,
            |manager| manager.can_undo(),
            |manager| { manager.undo_blocking(); }
        )
    })
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        with_write_lock_if(
            &undo_manager,
            |manager| manager.can_redo(),
            |manager| { manager.redo_blocking(); }
        )
    })
}
