use std::mem;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, MutexGuard};
use yrs::{TransactionMut, UndoManager};

use crate::undo::try_release;

pub(crate) type Unobserve = Box<dyn FnOnce(&TransactionMut) + Send>;

/// Teardown work that needs a document's store, queued on the document.
///
/// Resource destructors run on whichever scheduler thread frees the resource, possibly
/// while the document's worker is in the middle of an operation on another thread. If a
/// destructor took the store lock there, even briefly, that operation would fail with
/// `TransactionAcqError`. So destructors only queue their work here, and it is carried out
/// by the next operation on the document, which already holds (or just released) the store.
#[derive(Default)]
pub(crate) struct Deferred {
    unobserves: Mutex<Vec<Unobserve>>,
    has_unobserves: AtomicBool,
    undo_managers: Mutex<Vec<UndoManager>>,
    has_undo_managers: AtomicBool,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl Deferred {
    pub(crate) fn defer_unobserve(&self, unobserve: Unobserve) {
        lock(&self.unobserves).push(unobserve);
        self.has_unobserves.store(true, Ordering::Release);
    }

    /// Removes observers queued by dropped subscriptions, using a transaction on this document.
    pub(crate) fn run_unobserves(&self, txn: &TransactionMut) {
        if !self.has_unobserves.load(Ordering::Acquire) {
            return;
        }
        let pending = {
            let mut queue = lock(&self.unobserves);
            self.has_unobserves.store(false, Ordering::Release);
            mem::take(&mut *queue)
        };
        for unobserve in pending {
            unobserve(txn);
        }
    }

    pub(crate) fn defer_undo_manager(&self, manager: UndoManager) {
        lock(&self.undo_managers).push(manager);
        self.has_undo_managers.store(true, Ordering::Release);
    }

    /// Frees undo managers dropped since the last call. Detaching a manager takes its own
    /// transaction, so call this only once the current operation has released the store.
    pub(crate) fn release_undo_managers(&self) {
        if !self.has_undo_managers.load(Ordering::Acquire) {
            return;
        }
        let pending = {
            let mut queue = lock(&self.undo_managers);
            self.has_undo_managers.store(false, Ordering::Release);
            mem::take(&mut *queue)
        };
        let still_busy: Vec<UndoManager> = pending
            .into_iter()
            .filter_map(|manager| try_release(manager).err())
            .collect();
        if !still_busy.is_empty() {
            lock(&self.undo_managers).extend(still_busy);
            self.has_undo_managers.store(true, Ordering::Release);
        }
    }
}

impl Drop for Deferred {
    fn drop(&mut self) {
        let managers = mem::take(
            self.undo_managers
                .get_mut()
                .unwrap_or_else(|poisoned| poisoned.into_inner()),
        );
        for manager in managers {
            if let Err(manager) = try_release(manager) {
                // Its observers still point at it, so freeing it would leave them dangling.
                mem::forget(manager);
            }
        }
    }
}
