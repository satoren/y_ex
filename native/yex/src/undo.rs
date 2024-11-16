use crate::{
    doc::{DocResource},
    error::NifError,
    ENV,
    NifDoc,
};
use rustler::{Env, NifStruct, ResourceArc};
use std::sync::Mutex;
use std::collections::HashSet;
use yrs::undo::{UndoManager, Options as UndoOptions};
use yrs::Origin;

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Options"]
pub struct NifUndoManagerOptions {
    pub capture_timeout_millis: u64,
    pub tracked_origins: Vec<String>,
}

pub struct UndoManagerResource(pub Mutex<UndoManager<()>>);

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    pub doc: ResourceArc<DocResource>,
    pub manager: ResourceArc<UndoManagerResource>,
    pub options: NifUndoManagerOptions,
}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    options: NifUndoManagerOptions,
) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let mut undo_options = UndoOptions::default();
        undo_options.capture_timeout_millis = options.capture_timeout_millis;
        
        let tracked_origins: HashSet<Origin> = options.tracked_origins
            .iter()
            .map(|s| Origin::from(s.as_str()))
            .collect();
        undo_options.tracked_origins = tracked_origins;

        let manager = UndoManager::with_options(&doc.reference.0.doc, undo_options);
        let manager_resource = ResourceArc::new(UndoManagerResource(Mutex::new(manager)));

        Ok(NifUndoManager { 
            doc: doc.reference,
            manager: manager_resource,
            options,
        })
    })
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    manager: ResourceArc<UndoManagerResource>,
    origin: String,
) -> Result<(), NifError> {
    let mut mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    mgr.include_origin(Origin::from(origin.as_str()));
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    manager: ResourceArc<UndoManagerResource>,
    origin: String,
) -> Result<(), NifError> {
    let mut mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    mgr.exclude_origin(Origin::from(origin.as_str()));
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_undo(
    manager: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    let mut mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    mgr.undo_blocking();
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_redo(
    manager: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    let mut mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    mgr.redo_blocking();
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_clear(
    manager: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    let mut mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    mgr.clear();
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_can_undo(
    manager: ResourceArc<UndoManagerResource>,
) -> Result<bool, NifError> {
    let mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    Ok(mgr.can_undo())
}

#[rustler::nif]
pub fn undo_manager_can_redo(
    manager: ResourceArc<UndoManagerResource>,
) -> Result<bool, NifError> {
    let mgr = manager.0.lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    
    Ok(mgr.can_redo())
}