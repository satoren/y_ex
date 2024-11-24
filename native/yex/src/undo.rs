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
pub fn undo_manager_exclude_origin(
    env: Env<'_>, 
    undo_manager: NifUndoManager, 
    origin_term: Term
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(origin) = term_to_origin_binary(origin_term) {
            manager.exclude_origin(origin.as_slice());
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

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    scope: SharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        match scope {
            SharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get text branch reference".to_string()))?;
                manager.expand_scope(&branch);
            },
            SharedTypeInput::Array(array) => {
                let branch = array.readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get array branch reference".to_string()))?;
                manager.expand_scope(&branch);
            },
            SharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get map branch reference".to_string()))?;
                manager.expand_scope(&branch);
            },
        }
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut manager = undo_manager.reference.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        manager.reset();
        Ok(())
    })
}
