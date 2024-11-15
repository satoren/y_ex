use crate::{
    doc::{DocResource, TransactionResource},
    error::NifError,
    ENV,
};
use rustler::{Env, NifStruct, ResourceArc};
use std::sync::Mutex;
use yrs::undo::{UndoManager, Options as UndoOptions};

type YUndoManager = UndoManager<()>;

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    doc: ResourceArc<DocResource>,
    manager: ResourceArc<UndoManagerResource>,
}

pub struct UndoManagerResource(pub Mutex<YUndoManager>);

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: ResourceArc<DocResource>,
    _scope: ResourceArc<DocResource>,
    capture_timeout_millis: Option<u64>,
) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let mut options = UndoOptions::default();
        if let Some(timeout) = capture_timeout_millis {
            options.capture_timeout_millis = timeout;
        }

        let manager = UndoManager::with_options(&doc.0.doc, options);
        let manager_resource = ResourceArc::new(UndoManagerResource(Mutex::new(manager)));

        Ok(NifUndoManager { 
            doc, 
            manager: manager_resource 
        })
    })
}

#[rustler::nif]
pub fn undo_manager_undo(
    manager: NifUndoManager,
    _current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    let mut mgr = manager
        .manager
        .0
        .lock()
        .map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    mgr.undo_blocking();
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_redo(
    manager: NifUndoManager,
    _current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    let mut mgr = manager.manager.0.lock().map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    mgr.redo_blocking();
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_can_undo(
    manager: NifUndoManager,
    _current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<bool, NifError> {
    let mgr = manager.manager.0.lock().map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    Ok(mgr.can_undo())
}

#[rustler::nif]
pub fn undo_manager_can_redo(
    manager: NifUndoManager,
    _current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<bool, NifError> {
    let mgr = manager.manager.0.lock().map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    Ok(mgr.can_redo())
}

#[rustler::nif]
pub fn undo_manager_clear(
    manager: NifUndoManager,
    _current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    let mut mgr = manager.manager.0.lock().map_err(|_| NifError::Message("Failed to lock undo manager".into()))?;
    mgr.clear();
    Ok(())
} 