use crate::{
    atoms, shared_type::NifSharedType, utils::term_to_origin_binary, wrap::NifWrap,
    yinput::NifSharedTypeInput, Error, NifDoc, ENV,
};

use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc, Term};
use std::mem::ManuallyDrop;
use std::ops::Deref;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, RwLock};
use yrs::{undo::Options as UndoOptions, UndoManager};

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
    doc: NifDoc,
}

pub struct UndoManagerWrapper {
    manager: ManuallyDrop<UndoManager>,
}

impl UndoManagerWrapper {
    pub fn new(manager: UndoManager) -> Self {
        Self {
            manager: ManuallyDrop::new(manager),
        }
    }
}

// yrs' `UndoManager::drop` unwraps `unobserve_*` calls that need exclusive access to the
// document store, so dropping it while a transaction is open panics, and a panic in a
// resource destructor aborts the VM. Its observers also hold raw pointers to the manager,
// so it can't simply be freed without detaching them first.
impl Drop for UndoManagerWrapper {
    fn drop(&mut self) {
        // SAFETY: `manager` is not accessed again after being taken here.
        let manager = unsafe { ManuallyDrop::take(&mut self.manager) };
        if let Err(manager) = try_release(manager) {
            let mut parked = lock_parked();
            parked.push(manager);
            HAS_PARKED.store(true, Ordering::Release);
        }
    }
}

/// Managers whose document store was busy when they were dropped. Their observers stay
/// registered (and keep recording into them) until they are released.
static PARKED: Mutex<Vec<UndoManager>> = Mutex::new(Vec::new());
/// Lock-free fast path for `release_parked_undo_managers`; only written under `PARKED`.
static HAS_PARKED: AtomicBool = AtomicBool::new(false);

fn lock_parked() -> std::sync::MutexGuard<'static, Vec<UndoManager>> {
    PARKED
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Detaches `manager` from its documents and frees it, or hands it back if a store is busy.
fn try_release(manager: UndoManager) -> Result<(), UndoManager> {
    let origin = manager.as_origin();
    let mut detached = true;
    for doc in manager.docs() {
        match yrs::Transact::try_transact_mut(doc) {
            Ok(txn) => {
                txn.unobserve_destroy(origin.clone());
                txn.unobserve_after_transaction(origin.clone());
            }
            Err(_) => detached = false,
        }
    }
    if !detached {
        return Err(manager);
    }
    // yrs' Drop repeats the (now no-op) unobserve calls, which still need the store. If
    // another transaction wins the race for it, the panic is contained here, and freeing the
    // manager is sound because no observer points at it anymore.
    let _ = std::panic::catch_unwind(AssertUnwindSafe(|| drop(manager)));
    Ok(())
}

/// Retries releasing parked managers. Call once a transaction has been closed.
pub(crate) fn release_parked_undo_managers() {
    if !HAS_PARKED.load(Ordering::Acquire) {
        return;
    }
    let parked = {
        let mut parked = lock_parked();
        HAS_PARKED.store(false, Ordering::Release);
        std::mem::take(&mut *parked)
    };
    let still_busy: Vec<UndoManager> = parked
        .into_iter()
        .filter_map(|manager| try_release(manager).err())
        .collect();
    if !still_busy.is_empty() {
        let mut parked = lock_parked();
        parked.extend(still_busy);
        HAS_PARKED.store(true, Ordering::Release);
    }
}

pub type UndoManagerResource = NifWrap<RwLock<UndoManagerWrapper>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Options"]
pub struct NifUndoOptions {
    pub capture_timeout: u64,
}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
) -> NifResult<(Atom, NifUndoManager)> {
    ENV.set(&mut env.clone(), || match scope {
        NifSharedTypeInput::Text(text) => create_undo_manager(env, doc, text),
        NifSharedTypeInput::Array(array) => create_undo_manager(env, doc, array),
        NifSharedTypeInput::Map(map) => create_undo_manager(env, doc, map),
        NifSharedTypeInput::XmlText(text) => create_undo_manager(env, doc, text),
        NifSharedTypeInput::XmlElement(element) => create_undo_manager(env, doc, element),
        NifSharedTypeInput::XmlFragment(fragment) => create_undo_manager(env, doc, fragment),
        NifSharedTypeInput::WeakLink(weak_link) => create_undo_manager(env, doc, weak_link),
    })
}

fn create_undo_manager<T: NifSharedType>(
    env: Env<'_>,
    doc: NifDoc,
    scope: T,
) -> NifResult<(Atom, NifUndoManager)> {
    create_undo_manager_with_options(
        env,
        doc,
        scope,
        NifUndoOptions {
            capture_timeout: 500,
        },
    )
}

// Raises TransactionAcqError when a transaction is open, instead of folding it
// into the generic lookup failure message.
fn branch_ref<T: NifSharedType>(scope: &T, message: &str) -> NifResult<T::RefType> {
    let txn = yrs::Transact::try_transact(&scope.doc().reference.doc).map_err(Error::from)?;
    scope
        .get_ref(&txn)
        .map_err(|_| Error::Message(message.to_string()).into())
}

fn create_undo_manager_with_options<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions,
) -> NifResult<(Atom, NifUndoManager)> {
    let branch = branch_ref(&scope, "Failed to get branch reference")?;

    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };

    let mut undo_manager = UndoManager::with_options(undo_options);
    undo_manager.expand_scope(&doc, &branch);
    let wrapper = UndoManagerWrapper::new(undo_manager);

    Ok((
        atoms::ok(),
        NifUndoManager {
            reference: ResourceArc::new(NifWrap(RwLock::new(wrapper))),
            doc,
        },
    ))
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
    options: NifUndoOptions,
) -> NifResult<(Atom, NifUndoManager)> {
    // Check if the document reference is valid by attempting to access its inner doc
    // will return an error tuple if it is not
    let _doc_ref = doc.reference.deref();

    match scope {
        NifSharedTypeInput::Text(text) => create_undo_manager_with_options(env, doc, text, options),
        NifSharedTypeInput::Array(array) => {
            create_undo_manager_with_options(env, doc, array, options)
        }
        NifSharedTypeInput::Map(map) => create_undo_manager_with_options(env, doc, map, options),
        NifSharedTypeInput::XmlText(text) => {
            create_undo_manager_with_options(env, doc, text, options)
        }
        NifSharedTypeInput::XmlElement(element) => {
            create_undo_manager_with_options(env, doc, element, options)
        }
        NifSharedTypeInput::XmlFragment(fragment) => {
            create_undo_manager_with_options(env, doc, fragment, options)
        }
        NifSharedTypeInput::WeakLink(weak_link) => {
            create_undo_manager_with_options(env, doc, weak_link, options)
        }
    }
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| Error::Message("Invalid origin term".to_string()))?;
        wrapper.manager.include_origin(origin.as_slice());

        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| Error::Message("Invalid origin term".to_string()))?;
        wrapper.manager.exclude_origin(origin.as_slice());

        Ok(atoms::ok())
    })
}

fn ensure_store_available(undo_manager: &NifUndoManager) -> Result<(), Error> {
    drop(yrs::Transact::try_transact(&undo_manager.doc.reference.doc).map_err(Error::from)?);
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env, undo_manager: NifUndoManager) -> NifResult<(Atom, bool)> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        ensure_store_available(&undo_manager)?;

        if !wrapper.manager.can_undo() {
            return Ok((atoms::ok(), false));
        }

        let changed = wrapper.manager.undo_blocking();
        Ok((atoms::ok(), changed))
    })
}

#[rustler::nif]
pub fn undo_manager_can_undo(undo_manager: NifUndoManager) -> NifResult<bool> {
    let wrapper = undo_manager
        .reference
        .0
        .read()
        .map_err(|_| Error::Message("Failed to acquire read lock".to_string()))?;

    Ok(wrapper.manager.can_undo())
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> NifResult<(Atom, bool)> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        ensure_store_available(&undo_manager)?;

        if !wrapper.manager.can_redo() {
            return Ok((atoms::ok(), false));
        }

        let changed = wrapper.manager.redo_blocking();
        Ok((atoms::ok(), changed))
    })
}

#[rustler::nif]
pub fn undo_manager_can_redo(undo_manager: NifUndoManager) -> NifResult<bool> {
    let wrapper = undo_manager
        .reference
        .0
        .read()
        .map_err(|_| Error::Message("Failed to acquire read lock".to_string()))?;

    Ok(wrapper.manager.can_redo())
}

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    scope: NifSharedTypeInput,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;
        let doc = undo_manager.doc;
        match scope {
            NifSharedTypeInput::Text(text) => {
                let branch = branch_ref(&text, "Failed to get text branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::Array(array) => {
                let branch = branch_ref(&array, "Failed to get array branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::Map(map) => {
                let branch = branch_ref(&map, "Failed to get map branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::XmlText(text) => {
                let branch = branch_ref(&text, "Failed to get xml text branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::XmlElement(element) => {
                let branch = branch_ref(&element, "Failed to get xml element branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::XmlFragment(fragment) => {
                let branch = branch_ref(&fragment, "Failed to get xml fragment branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
            NifSharedTypeInput::WeakLink(weak_link) => {
                let branch = branch_ref(&weak_link, "Failed to get weak link branch reference")?;
                wrapper.manager.expand_scope(doc.deref(), &branch);
            }
        }

        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(env: Env<'_>, undo_manager: NifUndoManager) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.reset();
        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        // UndoManager::clear_all takes a blocking read transaction, so hold a try_transact
        // read across it to fail instead of waiting when a transaction is open.
        let _store =
            yrs::Transact::try_transact(&undo_manager.doc.reference.doc).map_err(Error::from)?;
        wrapper.manager.clear_all();

        Ok(atoms::ok())
    })
}
