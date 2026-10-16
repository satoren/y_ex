use crate::{
    atoms,
    deferred::Deferred,
    doc::DocResource,
    error::ArgumentError,
    shared_type::NifSharedType,
    subscription::{CallbackState, NifSubscription, SubscriptionKey},
    term_box::TermBox,
    utils::{origin_to_term, term_to_origin_binary},
    wrap::NifWrap,
    yinput::{with_shared_type, NifSharedTypeInput},
    Error, NifDoc, ENV,
};

use rustler::{Atom, Encoder, Env, LocalPid, NifResult, NifStruct, ResourceArc, Term};
use scoped_thread_local::scoped_thread_local;
use std::mem::ManuallyDrop;
use std::ops::Deref;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};
use yrs::undo::{Event, EventKind, Options as UndoOptions, StackClearedEvent};
use yrs::Origin;

pub(crate) type YexUndoManager = yrs::undo::UndoManager<StackMeta>;

/// What y_ex keeps on each stack item: an id that is stable for the item's life (also
/// across merges, since yrs moves the meta out and back for `:updated`), and the term
/// set by `undo_manager_put_meta`. The meta lives and dies with its item.
pub struct StackMeta {
    id: u64,
    value: Mutex<Option<TermBox>>,
}

impl Default for StackMeta {
    fn default() -> Self {
        static NEXT_ID: AtomicU64 = AtomicU64::new(1);
        StackMeta {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            value: Mutex::new(None),
        }
    }
}

impl StackMeta {
    fn value(&self) -> MutexGuard<'_, Option<TermBox>> {
        lock(&self.value)
    }

    fn get<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self.value().as_ref() {
            Some(value) => value.get(env),
            None => rustler::types::atom::nil().encode(env),
        }
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[derive(NifStruct, Clone)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
    doc: NifDoc,
}

// The manager whose undo or redo is running on this thread, with its origin. yrs tags
// those transactions with the manager's address, so `crate::utils::origin_to_term`
// uses this to report the origin as the manager itself.
scoped_thread_local!(static ACTIVE: (yrs::Origin, NifUndoManager));

/// The manager running an undo or redo with `origin` on this thread, encoded in `env`.
pub(crate) fn active_manager_term<'a>(env: Env<'a>, origin: &yrs::Origin) -> Option<Term<'a>> {
    if !ACTIVE.is_set() {
        return None;
    }
    ACTIVE.with(|(active, manager)| (active == origin).then(|| manager.encode(env)))
}

pub struct UndoManagerWrapper {
    manager: ManuallyDrop<YexUndoManager>,
    doc: ResourceArc<DocResource>,
}

impl UndoManagerWrapper {
    pub fn new(manager: YexUndoManager, doc: ResourceArc<DocResource>) -> Self {
        Self {
            manager: ManuallyDrop::new(manager),
            doc,
        }
    }
}

// yrs' `UndoManager::drop` unwraps `unobserve_*` calls that need exclusive access to the
// document store, so dropping it while a transaction is open panics, and a panic in a
// resource destructor aborts the VM. Its observers also hold raw pointers to the manager,
// so it can't simply be freed without detaching them first. Detaching takes the store,
// which a destructor must not do (see `crate::deferred`), so the manager is handed to its
// document and released by the document's next operation.
impl Drop for UndoManagerWrapper {
    fn drop(&mut self) {
        // SAFETY: `manager` is not accessed again after being taken here.
        let manager = unsafe { ManuallyDrop::take(&mut self.manager) };
        // Free the meta terms now: one holding this document (a `Yex.StickyIndex`, say)
        // would otherwise keep it alive through its own deferred queue until its next
        // operation, which may never come.
        for item in manager.undo_stack().iter().chain(manager.redo_stack()) {
            *item.meta().value() = None;
        }
        self.doc
            .deferred
            .defer_undo_manager(manager, self.doc.doc.clone());
    }
}

/// Detaches `manager` from its documents and frees it, or hands it back if a store is busy.
///
/// `home` is the document the manager was created on. It is detached even when the manager
/// no longer lists it: after `Yex.Doc.destroy/1` dropped it from the list, a racing
/// `expand_scope` can have registered a destroy observer there again (see `expand`), and
/// a second destroy would call it after the manager is freed. Removing by origin cannot
/// hit another manager's observer, since the origin is this manager's own address.
pub(crate) fn try_release(manager: YexUndoManager, home: &yrs::Doc) -> Result<(), YexUndoManager> {
    let origin = manager.as_origin();
    let mut detached = true;
    let home_listed = manager.docs().any(|doc| yrs::Doc::ptr_eq(doc, home));
    let unlisted_home = (!home_listed).then_some(home);
    for doc in manager.docs().chain(unlisted_home) {
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

/// The manager and the stack-event observer keys waiting to be removed from it.
///
/// yrs reaches the manager's state through a raw pointer from its `after_transaction`
/// observer, without this lock, and its observer lists are mutated while they fire. So the
/// stacks and observers are only touched on the document's worker, which also runs every
/// commit: reads of the stacks need no store guard, and a subscription dropped on another
/// thread queues its key in `pending_unobserves` instead of removing its observers. The
/// queue sits beside the lock so that dropping never waits on it; `read` and `write` drain it.
pub struct UndoManagerState {
    wrapper: RwLock<UndoManagerWrapper>,
    pending_unobserves: Mutex<Vec<Origin>>,
}

impl UndoManagerState {
    fn new(wrapper: UndoManagerWrapper) -> Self {
        UndoManagerState {
            wrapper: RwLock::new(wrapper),
            pending_unobserves: Mutex::new(Vec::new()),
        }
    }

    fn read(&self) -> NifResult<RwLockReadGuard<'_, UndoManagerWrapper>> {
        // Read-only calls also run on the worker, so drain queued removals here too:
        // otherwise they wait for the next write, which a read-only workload never makes.
        if !lock(&self.pending_unobserves).is_empty() {
            drop(self.write()?);
        }
        self.wrapper
            .read()
            .map_err(|_| Error::Message("Failed to acquire read lock".to_string()).into())
    }

    fn write(&self) -> NifResult<RwLockWriteGuard<'_, UndoManagerWrapper>> {
        let mut wrapper = self
            .wrapper
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;
        let pending = std::mem::take(&mut *lock(&self.pending_unobserves));
        for key in pending {
            unobserve_stack_events(&mut wrapper.manager, key);
        }
        Ok(wrapper)
    }

    /// Removes the stack-event observers registered under `key`. Run on the worker.
    pub(crate) fn unobserve(&self, key: &Origin) {
        match self.write() {
            Ok(mut wrapper) => unobserve_stack_events(&mut wrapper.manager, key.clone()),
            Err(_) => self.defer_unobserve(key.clone()),
        }
    }

    /// Queues the removal of the observers registered under `key` for the next `read` or `write`.
    pub(crate) fn defer_unobserve(&self, key: Origin) {
        lock(&self.pending_unobserves).push(key);
    }
}

fn unobserve_stack_events(manager: &mut YexUndoManager, key: Origin) {
    manager.unobserve_item_added(key.clone());
    manager.unobserve_item_updated(key.clone());
    manager.unobserve_item_popped(key.clone());
    manager.unobserve_stack_cleared(key);
}

pub type UndoManagerResource = NifWrap<UndoManagerState>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Options"]
pub struct NifUndoOptions<'a> {
    pub capture_timeout: u64,
    pub tracked_origins: Option<Vec<Term<'a>>>,
}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
) -> NifResult<(Atom, NifUndoManager)> {
    ENV.set(
        &mut env.clone(),
        || with_shared_type!(scope, t => create_undo_manager(env, doc, t)),
    )
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
            tracked_origins: None,
        },
    )
}

// Raises ArgumentError when `scope` belongs to a document other than `doc`: the manager
// observes only `doc`, so yrs would accept the scope and never capture its changes.
// Compares the yrs document, not the wrapper: one subdocument can have several `Yex.Doc`
// wrappers.
fn ensure_same_doc<T: NifSharedType>(doc: &NifDoc, scope: &T) -> NifResult<()> {
    if yrs::Doc::ptr_eq(&doc.reference.doc, &scope.doc().reference.doc) {
        Ok(())
    } else {
        Err(ArgumentError::raise(
            "scope belongs to a different document",
        ))
    }
}

// Raises TransactionAcqError when a transaction is open, instead of folding it
// into the generic lookup failure message.
fn branch_ref<T: NifSharedType>(scope: &T, message: &str) -> NifResult<T::RefType> {
    let txn = yrs::Transact::try_transact(&scope.doc().reference.doc).map_err(Error::from)?;
    scope
        .get_ref(&txn)
        .map_err(|_| Error::Message(message.to_string()).into())
}

// yrs 0.28 `UndoManager::expand_scope` registers two observers on the document the first
// time it sees it, unwrapping a `try_transact_mut` for each, so it panics when another
// thread holds the store (y-crdt/y-crdt#665 makes it fallible). These helpers contain the
// panic and raise `TransactionAcqError` instead.

/// Attaches a new manager to `doc`. If the panic comes after the destroy observer was
/// registered, that observer holds a raw pointer into the manager, so the manager is kept
/// until the next mutable transaction y_ex opens on the document (`Yex.Doc.transaction/3`
/// or any mutating call) removes the observers, and leaked if that never happens.
fn attach<R: AsRef<yrs::branch::Branch>>(
    mut manager: YexUndoManager,
    doc: &yrs::Doc,
    deferred: &Deferred,
    branch: &R,
) -> Result<YexUndoManager, Error> {
    let expanded = std::panic::catch_unwind(AssertUnwindSafe(|| manager.expand_scope(doc, branch)));
    if expanded.is_ok() {
        return Ok(manager);
    }
    defer_detach(manager, deferred);
    Err(Error::Transaction)
}

/// Queues removal of the observers a failed first `expand_scope` may have left on the
/// document, then frees `manager`.
fn defer_detach(manager: YexUndoManager, deferred: &Deferred) {
    let origin = manager.as_origin();
    let manager = ManuallyDrop::new(manager);
    deferred.defer_unobserve(Box::new(move |txn| {
        txn.unobserve_destroy(origin.clone());
        txn.unobserve_after_transaction(origin);
        // The panic came before the document was recorded in the manager, so its Drop
        // has no observers to remove and does not touch the store.
        drop(ManuallyDrop::into_inner(manager));
    }));
}

/// Expands the scope of an attached manager. The panic is only reachable here after
/// `Yex.Doc.destroy/1` detached the manager from its document. A half-registered destroy
/// observer is left in place, since removing it by origin now could also remove a later,
/// complete one; `try_release` removes it when the manager is freed.
fn expand<R: AsRef<yrs::branch::Branch>>(
    manager: &mut YexUndoManager,
    doc: &NifDoc,
    branch: &R,
) -> Result<(), Error> {
    std::panic::catch_unwind(AssertUnwindSafe(|| manager.expand_scope(doc, branch)))
        .map_err(|_| Error::Transaction)
}

/// Adds `scope` to an existing manager. Raises `TransactionAcqError` instead of panicking
/// when the scope's document is busy (see `expand`).
fn expand_scope<T: NifSharedType>(
    manager: &mut YexUndoManager,
    doc: &NifDoc,
    scope: &T,
) -> NifResult<()> {
    ensure_same_doc(doc, scope)?;
    let branch = branch_ref(scope, "Failed to get branch reference")?;
    expand(manager, doc, &branch)?;
    Ok(())
}

/// Builds a manager tracking `scope` and attaches it to `doc` (see `attach`).
fn create_undo_manager_with_options<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions<'_>,
) -> NifResult<(Atom, NifUndoManager)> {
    ensure_same_doc(&doc, &scope)?;
    let branch = branch_ref(&scope, "Failed to get branch reference")?;

    let mut undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };
    for origin_term in options.tracked_origins.unwrap_or_default() {
        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| Error::Message("Invalid origin term".to_string()))?;
        undo_options
            .tracked_origins
            .insert(origin.as_slice().into());
    }

    let undo_manager = attach(
        YexUndoManager::with_options(undo_options),
        &doc,
        &doc.reference.deferred,
        &branch,
    )?;
    let wrapper = UndoManagerWrapper::new(undo_manager, doc.reference.clone());

    Ok((
        atoms::ok(),
        NifUndoManager {
            reference: ResourceArc::new(NifWrap(UndoManagerState::new(wrapper))),
            doc,
        },
    ))
}

/// NIF behind `Yex.UndoManager.new/2` and `new_with_options/3`.
#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
    options: NifUndoOptions<'_>,
) -> NifResult<(Atom, NifUndoManager)> {
    // Check if the document reference is valid by attempting to access its inner doc
    // will return an error tuple if it is not
    let _doc_ref = doc.reference.deref();

    with_shared_type!(scope, t => create_undo_manager_with_options(env, doc, t, options))
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.write()?;

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
        let mut wrapper = undo_manager.reference.write()?;

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
        let mut wrapper = undo_manager.reference.write()?;

        ensure_store_available(&undo_manager)?;

        if !wrapper.manager.can_undo() {
            return Ok((atoms::ok(), false));
        }

        let mut active = (wrapper.manager.as_origin(), undo_manager.clone());
        let changed = ACTIVE.set(&mut active, || wrapper.manager.undo_blocking());
        Ok((atoms::ok(), changed))
    })
}

#[rustler::nif]
pub fn undo_manager_can_undo(undo_manager: NifUndoManager) -> NifResult<bool> {
    let wrapper = undo_manager.reference.read()?;

    Ok(wrapper.manager.can_undo())
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> NifResult<(Atom, bool)> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.write()?;

        ensure_store_available(&undo_manager)?;

        if !wrapper.manager.can_redo() {
            return Ok((atoms::ok(), false));
        }

        let mut active = (wrapper.manager.as_origin(), undo_manager.clone());
        let changed = ACTIVE.set(&mut active, || wrapper.manager.redo_blocking());
        Ok((atoms::ok(), changed))
    })
}

#[rustler::nif]
pub fn undo_manager_can_redo(undo_manager: NifUndoManager) -> NifResult<bool> {
    let wrapper = undo_manager.reference.read()?;

    Ok(wrapper.manager.can_redo())
}

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    scope: NifSharedTypeInput,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.write()?;
        let manager = &mut wrapper.manager;
        let doc = &undo_manager.doc;
        with_shared_type!(scope, t => expand_scope(manager, doc, &t))?;

        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(env: Env<'_>, undo_manager: NifUndoManager) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.write()?;

        wrapper.manager.reset();
        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.write()?;

        // UndoManager::clear_all takes a blocking read transaction, so hold a try_transact
        // read across it to fail instead of waiting when a transaction is open.
        let _store =
            yrs::Transact::try_transact(&undo_manager.doc.reference.doc).map_err(Error::from)?;
        wrapper.manager.clear_all();

        Ok(atoms::ok())
    })
}

/// Where a subscription's stack events go: the subscriber, its reference and metadata.
type EventTarget = (LocalPid, TermBox, TermBox);

#[derive(NifStruct)]
#[module = "Yex.UndoManager.StackClearedEvent"]
struct NifStackClearedEvent {
    undo_stack_cleared: bool,
    redo_stack_cleared: bool,
}

/// Encodes `%Yex.UndoManager.StackItemEvent{}` by hand: its `type` field is a Rust keyword.
fn stack_item_event<'a>(env: &mut Env<'a>, event_type: Atom, e: &Event<StackMeta>) -> Term<'a> {
    let kind = match e.kind() {
        EventKind::Undo => atoms::undo(),
        EventKind::Redo => atoms::redo(),
    };
    let origin = origin_to_term(env, e.origin());
    let env = *env;
    let module = Atom::from_str(env, "Elixir.Yex.UndoManager.StackItemEvent")
        .expect("valid atom")
        .encode(env);
    let pairs = [
        (atoms::struct_().encode(env), module),
        (atoms::type_().encode(env), event_type.encode(env)),
        (atoms::kind().encode(env), kind.encode(env)),
        (atoms::item().encode(env), e.meta().id.encode(env)),
        (atoms::origin().encode(env), origin),
        (atoms::meta().encode(env), e.meta().get(env)),
    ];
    Term::map_from_pairs(env, &pairs).expect("distinct keys")
}

enum StackEvent<'e> {
    Item(Atom, &'e Event<StackMeta>),
    Cleared(&'e StackClearedEvent),
}

fn notify(state: &CallbackState<EventTarget>, event: StackEvent<'_>) {
    // `None` also when no NIF env is set (a transaction freed with its killed process).
    let Some(state) = state.get() else {
        return;
    };
    let (pid, ref_term, metadata) = &*state;
    ENV.with(|env| {
        let event = match event {
            StackEvent::Item(event_type, e) => stack_item_event(env, event_type, e),
            StackEvent::Cleared(e) => NifStackClearedEvent {
                undo_stack_cleared: e.undo_stack_cleared,
                redo_stack_cleared: e.redo_stack_cleared,
            }
            .encode(*env),
        };
        let _ = env.send(
            pid,
            (
                atoms::undo_manager_event(),
                ref_term.get(*env),
                event,
                metadata.get(*env),
            ),
        );
    })
}

// The callbacks capture only `state`: holding the manager would keep it alive from its own
// observers, and popped (and added, during undo) run while undo and redo hold its lock.
fn item_callback(
    state: CallbackState<EventTarget>,
    event_type: Atom,
) -> impl FnMut(&yrs::TransactionMut, &mut Event<StackMeta>) + Send + Sync + 'static {
    move |_txn, e| notify(&state, StackEvent::Item(event_type, e))
}

#[rustler::nif]
pub fn undo_manager_observe(
    undo_manager: NifUndoManager,
    pid: LocalPid,
    ref_term: Term<'_>,
    metadata: Term<'_>,
) -> NifResult<NifSubscription> {
    let (sub_key, state) =
        SubscriptionKey::new((pid, TermBox::new(ref_term), TermBox::new(metadata)));
    {
        let mut wrapper = undo_manager.reference.write()?;
        let manager = &mut wrapper.manager;
        let key = &sub_key.key;
        manager.observe_item_added(key.clone(), item_callback(state.clone(), atoms::added()));
        manager.observe_item_updated(key.clone(), item_callback(state.clone(), atoms::updated()));
        manager.observe_item_popped(key.clone(), item_callback(state.clone(), atoms::popped()));
        manager.observe_stack_cleared(key.clone(), move |e| notify(&state, StackEvent::Cleared(e)));
    }
    let doc = undo_manager.doc.clone();
    Ok(NifSubscription::new(
        sub_key.undo_manager(undo_manager.reference),
        doc,
    ))
}

#[rustler::nif]
pub fn undo_manager_undo_stack_size(undo_manager: NifUndoManager) -> NifResult<usize> {
    Ok(undo_manager.reference.read()?.manager.undo_stack().len())
}

#[rustler::nif]
pub fn undo_manager_redo_stack_size(undo_manager: NifUndoManager) -> NifResult<usize> {
    Ok(undo_manager.reference.read()?.manager.redo_stack().len())
}

/// Runs `f` on the meta of the stack item `id`, or returns `{:error, :not_found}`.
fn with_stack_meta<'a, F>(
    env: Env<'a>,
    undo_manager: &NifUndoManager,
    id: u64,
    f: F,
) -> NifResult<Term<'a>>
where
    F: FnOnce(&StackMeta) -> Term<'a>,
{
    let wrapper = undo_manager.reference.read()?;
    let manager = &wrapper.manager;
    let item = manager
        .undo_stack()
        .iter()
        .chain(manager.redo_stack())
        .find(|item| item.meta().id == id);
    Ok(match item {
        Some(item) => f(item.meta()),
        None => (atoms::error(), atoms::not_found()).encode(env),
    })
}

#[rustler::nif]
pub fn undo_manager_get_meta<'a>(
    env: Env<'a>,
    undo_manager: NifUndoManager,
    id: u64,
) -> NifResult<Term<'a>> {
    with_stack_meta(env, &undo_manager, id, |meta| {
        (atoms::ok(), meta.get(env)).encode(env)
    })
}

#[rustler::nif]
pub fn undo_manager_put_meta<'a>(
    env: Env<'a>,
    undo_manager: NifUndoManager,
    id: u64,
    value: Term<'a>,
) -> NifResult<Term<'a>> {
    with_stack_meta(env, &undo_manager, id, |meta| {
        *meta.value() = Some(TermBox::new(value));
        atoms::ok().encode(env)
    })
}

#[cfg(test)]
mod tests {
    use super::{attach, defer_detach, try_release, StackMeta, YexUndoManager};
    use crate::deferred::Deferred;
    use crate::Error;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};
    use yrs::{Doc, Text, Transact};

    #[test]
    fn attach_while_a_transaction_is_open_fails_instead_of_panicking() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let deferred = Deferred::default();

        let read = doc.transact();
        let result = attach(YexUndoManager::new(), &doc, &deferred, &text);
        assert!(matches!(result, Err(Error::Transaction)));
        drop(read);

        deferred.run_unobserves(&doc.transact_mut());
        let manager = attach(YexUndoManager::new(), &doc, &deferred, &text).unwrap();
        text.insert(&mut doc.transact_mut(), 0, "a");
        assert!(manager.can_undo());
    }

    // The panic between the two observer registrations cannot be timed from a test, so
    // this registers the destroy observer the first one would have left behind.
    #[test]
    fn defer_detach_removes_a_half_registered_destroy_observer() {
        let doc = Doc::new();
        let deferred = Deferred::default();
        let manager = YexUndoManager::new();
        let fired = Arc::new(AtomicBool::new(false));
        let flag = fired.clone();
        doc.observe_destroy(manager.as_origin(), move |_, _| {
            flag.store(true, Ordering::SeqCst)
        })
        .unwrap();

        defer_detach(manager, &deferred);
        deferred.run_unobserves(&doc.transact_mut());
        doc.destroy(None);
        assert!(!fired.load(Ordering::SeqCst));
    }

    // A manager whose document was destroyed no longer lists it, but `expand_scope` can
    // have left a destroy observer there. Releasing it must still remove that observer.
    #[test]
    fn try_release_removes_observers_from_the_home_document() {
        let doc = Doc::new();
        let manager = YexUndoManager::new();
        let fired = Arc::new(AtomicBool::new(false));
        let flag = fired.clone();
        doc.observe_destroy(manager.as_origin(), move |_, _| {
            flag.store(true, Ordering::SeqCst)
        })
        .unwrap();
        assert_eq!(manager.docs().count(), 0);

        assert!(try_release(manager, &doc).is_ok());
        doc.destroy(None);
        assert!(!fired.load(Ordering::SeqCst));
    }

    #[test]
    fn stack_meta_ids_are_distinct_and_increasing() {
        let first = StackMeta::default();
        let second = StackMeta::default();
        assert!(second.id > first.id);
    }

    #[test]
    fn stack_item_id_follows_the_item_through_merge_and_pop() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let mut manager = YexUndoManager::new();
        manager.expand_scope(&doc, &text);

        let seen = Arc::new(Mutex::new(Vec::new()));
        let record = |name: &'static str| {
            let seen = seen.clone();
            move |_: &yrs::TransactionMut, e: &mut yrs::undo::Event<StackMeta>| {
                seen.lock().unwrap().push((name, e.meta().id));
            }
        };
        manager.observe_item_added("test", record("added"));
        manager.observe_item_updated("test", record("updated"));
        manager.observe_item_popped("test", record("popped"));

        text.insert(&mut doc.transact_mut(), 0, "a");
        text.insert(&mut doc.transact_mut(), 1, "b");
        assert_eq!(manager.undo_stack().len(), 1);
        let id = manager.undo_stack()[0].meta().id;

        assert!(manager.undo_blocking());
        let redo_id = manager.redo_stack()[0].meta().id;
        assert_ne!(redo_id, id);
        assert_eq!(
            *seen.lock().unwrap(),
            vec![
                ("added", id),
                ("updated", id),
                // undo pushes a new item onto the redo stack, then pops the original
                ("added", redo_id),
                ("popped", id),
            ]
        );
    }
}
