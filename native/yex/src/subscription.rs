use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use yrs::{Origin, TransactionMut};

use crate::{
    atoms,
    awareness::AwarenessResource,
    deferred::Unobserve,
    doc::{DocOperations, NifDoc},
    transaction::TransactionResource,
    wrap::NifWrap,
    ENV,
};

pub enum DocEvent {
    UpdateV1,
    UpdateV2,
    Subdocs,
}

pub enum AwarenessEvent {
    Update,
    Change,
}

enum Target {
    /// Doc and branch observers live in the document store. `None` once removed.
    Doc {
        doc: NifDoc,
        unobserve: Option<Unobserve>,
    },
    /// `None` once removed.
    Awareness {
        awareness: ResourceArc<AwarenessResource>,
        event: Option<AwarenessEvent>,
    },
}

/// Observers in yrs are registered under a key and removed via `unobserve(key)`, which
/// needs the document store. A dropped subscription must not take the store itself (see
/// `crate::deferred`), so unsubscribing happens in two steps: the callback state is
/// released right away, which silences the callback and frees the terms it captured (they
/// may reference the document itself), and the observer entry is removed with the next
/// transaction on the document.
pub struct Subscription {
    key: Origin,
    callback: Arc<dyn ReleaseCallback>,
    target: Target,
}

/// State an observer callback needs, released when its subscription is unsubscribed or
/// dropped. The callback does nothing once it has been released.
pub struct CallbackState<T>(Arc<Mutex<Option<Arc<T>>>>);

impl<T> CallbackState<T> {
    pub fn get(&self) -> Option<Arc<T>> {
        lock(&self.0).clone()
    }
}

trait ReleaseCallback: Send + Sync {
    fn release(&self);
}

impl<T: Send + Sync> ReleaseCallback for Mutex<Option<Arc<T>>> {
    fn release(&self) {
        // Drop the state outside the lock: freeing it may drop other resources.
        let state = lock(self).take();
        drop(state);
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Key and callback state handed to an observer callback before it's registered.
pub struct SubscriptionKey {
    pub key: Origin,
    callback: Arc<dyn ReleaseCallback>,
}

impl SubscriptionKey {
    pub fn new<T: Send + Sync + 'static>(state: T) -> (Self, CallbackState<T>) {
        static NEXT_ID: AtomicU64 = AtomicU64::new(1);
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let state = Arc::new(Mutex::new(Some(Arc::new(state))));
        (
            SubscriptionKey {
                key: Origin::from(format!("yex-subscription-{id}").as_str()),
                callback: state.clone(),
            },
            CallbackState(state),
        )
    }

    pub fn doc(self, doc: NifDoc, event: DocEvent) -> Subscription {
        let key = self.key.clone();
        let unobserve: Unobserve = Box::new(move |txn: &TransactionMut| {
            match event {
                DocEvent::UpdateV1 => txn.unobserve_update_v1(key),
                DocEvent::UpdateV2 => txn.unobserve_update_v2(key),
                DocEvent::Subdocs => txn.unobserve_subdocs(key),
            };
        });
        self.into_subscription(Target::Doc {
            doc,
            unobserve: Some(unobserve),
        })
    }

    /// `unobserve` has to resolve the branch through the transaction, since it may have been
    /// deleted (and garbage collected) in the meantime.
    pub fn branch<F>(self, doc: NifDoc, unobserve: F) -> Subscription
    where
        F: FnOnce(&TransactionMut, &Origin) + Send + 'static,
    {
        let key = self.key.clone();
        let unobserve: Unobserve = Box::new(move |txn: &TransactionMut| unobserve(txn, &key));
        self.into_subscription(Target::Doc {
            doc,
            unobserve: Some(unobserve),
        })
    }

    pub fn awareness(
        self,
        awareness: ResourceArc<AwarenessResource>,
        event: AwarenessEvent,
    ) -> Subscription {
        self.into_subscription(Target::Awareness {
            awareness,
            event: Some(event),
        })
    }

    fn into_subscription(self, target: Target) -> Subscription {
        Subscription {
            key: self.key,
            callback: self.callback,
            target,
        }
    }
}

impl Subscription {
    /// Explicit unsubscribe, run by the document's worker. Removes the observer with
    /// `current_transaction` when one is open, otherwise with a transaction of its own. If
    /// the store is held elsewhere, removal is left to the document's next transaction.
    fn unsubscribe(&mut self, current_transaction: Option<&TransactionMut>) {
        self.callback.release();
        match &mut self.target {
            Target::Doc { doc, unobserve } => {
                let Some(unobserve) = unobserve.take() else {
                    return;
                };
                match current_transaction {
                    Some(txn) => unobserve(txn),
                    None => {
                        let mut unobserve = Some(unobserve);
                        let _ = doc.with_transaction_mut(|txn| {
                            if let Some(unobserve) = unobserve.take() {
                                unobserve(txn);
                            }
                            Ok(())
                        });
                        if let Some(unobserve) = unobserve {
                            doc.reference.deferred.defer_unobserve(unobserve);
                        }
                    }
                }
            }
            Target::Awareness { .. } => self.remove_awareness_observer(),
        }
    }

    fn remove_awareness_observer(&mut self) {
        if let Target::Awareness { awareness, event } = &mut self.target {
            let Some(event) = event.take() else {
                return;
            };
            let mut awareness = awareness.0.lock().unwrap_or_else(|err| err.into_inner());
            match event {
                AwarenessEvent::Update => awareness.unobserve_update(self.key.clone()),
                AwarenessEvent::Change => awareness.unobserve_change(self.key.clone()),
            };
        }
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.callback.release();
        match &mut self.target {
            Target::Doc { doc, unobserve } => {
                if let Some(unobserve) = unobserve.take() {
                    doc.reference.deferred.defer_unobserve(unobserve);
                }
            }
            // The awareness lock never fails; at worst it waits for an awareness operation.
            Target::Awareness { .. } => self.remove_awareness_observer(),
        }
    }
}

pub type SubscriptionResource = NifWrap<Mutex<Subscription>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

#[derive(NifStruct)]
#[module = "Yex.Subscription"]
pub struct NifSubscription {
    pub(crate) reference: ResourceArc<SubscriptionResource>,
    pub(crate) doc: NifDoc,
}

impl NifSubscription {
    pub fn new(sub: Subscription, doc: NifDoc) -> Self {
        NifSubscription {
            reference: ResourceArc::new(NifWrap(Mutex::new(sub))),
            doc,
        }
    }
}

#[rustler::nif]
fn sub_unsubscribe(
    env: Env<'_>,
    sub: NifSubscription,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut inner = sub
            .reference
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let txn_guard = current_transaction
            .as_ref()
            .and_then(|txn| txn.0.read().ok());
        inner.unsubscribe(txn_guard.as_ref().and_then(|guard| guard.as_ref()));
        Ok(atoms::ok())
    })
}
