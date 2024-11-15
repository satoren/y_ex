use crate::{
    atoms,
    doc::{DocResource, TransactionResource},
    error::NifError,
    shared_type::{NifSharedType, SharedTypeId},
    ENV,
};
use rustler::{Env, LocalPid, NifStruct, ResourceArc, Term};
use std::collections::HashSet;
use yrs::undo::{UndoManager, Options as UndoOptions};
use yrs::{ReadTxn, SharedRef, Transact};

pub type UndoManagerResource = NifWrap<Mutex<YUndoManager>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    doc: ResourceArc<DocResource>,
    reference: SharedTypeId<UndoManager>,
}

impl NifSharedType for NifUndoManager {
    type RefType = UndoManager;
    const DELETED_ERROR: &'static str = "Undo manager has been deleted";

    fn doc(&self) -> &ResourceArc<DocResource> {
        &self.doc
    }

    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
}

#[rustler::nif]
fn undo_manager_new(
    env: Env<'_>,
    doc: ResourceArc<DocResource>,
    scope: SharedTypeId<UndoManager>,
    capture_timeout_millis: Option<u64>,
) -> Result<NifUndoManager, NifError> {
    ENV.set(&mut env.clone(), || {
        let mut options = UndoOptions::default();
        if let Some(timeout) = capture_timeout_millis {
            options.capture_timeout_millis = timeout;
        }

        let manager = UndoManager::with_options(&doc.0.doc, options);
        let reference = SharedTypeId::new(manager.hook());

        Ok(NifUndoManager { doc, reference })
    })
}

#[rustler::nif]
fn undo_manager_undo(
    env: Env<'_>,
    manager: NifUndoManager,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    manager.mutably(env, current_transaction, |txn| {
        if let Some(manager) = manager.reference.get(txn) {
            manager.undo(txn);
            Ok(())
        } else {
            Err(NifError::Message(NifUndoManager::DELETED_ERROR.to_string()))
        }
    })
}

#[rustler::nif]
fn undo_manager_redo(
    env: Env<'_>,
    manager: NifUndoManager,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    manager.mutably(env, current_transaction, |txn| {
        if let Some(manager) = manager.reference.get(txn) {
            manager.redo(txn);
            Ok(())
        } else {
            Err(NifError::Message(NifUndoManager::DELETED_ERROR.to_string()))
        }
    })
}

#[rustler::nif]
fn undo_manager_can_undo(
    manager: NifUndoManager,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<bool, NifError> {
    manager.readonly(current_transaction, |txn| {
        if let Some(manager) = manager.reference.get(txn) {
            Ok(manager.can_undo())
        } else {
            Err(NifError::Message(NifUndoManager::DELETED_ERROR.to_string()))
        }
    })
}

#[rustler::nif]
fn undo_manager_can_redo(
    manager: NifUndoManager,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<bool, NifError> {
    manager.readonly(current_transaction, |txn| {
        if let Some(manager) = manager.reference.get(txn) {
            Ok(manager.can_redo())
        } else {
            Err(NifError::Message(NifUndoManager::DELETED_ERROR.to_string()))
        }
    })
}

#[rustler::nif]
fn undo_manager_clear(
    env: Env<'_>,
    manager: NifUndoManager,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<(), NifError> {
    manager.mutably(env, current_transaction, |txn| {
        if let Some(manager) = manager.reference.get(txn) {
            manager.clear();
            Ok(())
        } else {
            Err(NifError::Message(NifUndoManager::DELETED_ERROR.to_string()))
        }
    })
} 