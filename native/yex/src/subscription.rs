use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use yrs::{Doc, Origin, TransactionMut};

use crate::{
    atoms,
    awareness::AwarenessResource,
    doc::NifDoc,
    transaction::{ReadTransaction, TransactionResource},
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

type UnobserveBranchFn = Box<dyn Fn(&ReadTransaction) -> bool + Send + Sync>;

enum Target {
    Doc {
        doc: Doc,
        event: DocEvent,
    },
    Branch {
        doc: NifDoc,
        unobserve: UnobserveBranchFn,
    },
    Awareness {
        awareness: ResourceArc<AwarenessResource>,
        event: AwarenessEvent,
    },
}

/// Observers in yrs are registered under a key and removed via `unobserve(key)`.
/// Removing a doc/branch observer needs access to the document store, which may be
/// unavailable while another transaction is open. The `active` flag guarantees that
/// callbacks stop immediately on unsubscribe even if the removal has to be retried later
/// (on drop).
pub struct Subscription {
    key: Origin,
    active: Arc<AtomicBool>,
    target: Target,
    removed: bool,
}

/// Key and activity flag handed to an observer callback before it's registered.
pub struct SubscriptionKey {
    pub key: Origin,
    pub active: Arc<AtomicBool>,
}

impl SubscriptionKey {
    pub fn new() -> Self {
        static NEXT_ID: AtomicU64 = AtomicU64::new(1);
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        SubscriptionKey {
            key: Origin::from(format!("yex-subscription-{id}").as_str()),
            active: Arc::new(AtomicBool::new(true)),
        }
    }

    pub fn doc(self, doc: Doc, event: DocEvent) -> Subscription {
        self.into_subscription(Target::Doc { doc, event })
    }

    pub fn branch<F>(self, doc: NifDoc, unobserve: F) -> Subscription
    where
        F: Fn(&ReadTransaction, &Origin) -> bool + Send + Sync + 'static,
    {
        let key = self.key.clone();
        self.into_subscription(Target::Branch {
            doc,
            unobserve: Box::new(move |txn| unobserve(txn, &key)),
        })
    }

    pub fn awareness(
        self,
        awareness: ResourceArc<AwarenessResource>,
        event: AwarenessEvent,
    ) -> Subscription {
        self.into_subscription(Target::Awareness { awareness, event })
    }

    fn into_subscription(self, target: Target) -> Subscription {
        Subscription {
            key: self.key,
            active: self.active,
            target,
            removed: false,
        }
    }
}

pub fn is_active(active: &AtomicBool) -> bool {
    active.load(Ordering::Acquire)
}

impl Subscription {
    fn unsubscribe(&mut self, current_transaction: Option<&TransactionMut>) {
        self.active.store(false, Ordering::Release);
        if self.removed {
            return;
        }
        self.removed = match &self.target {
            Target::Doc { doc, event } => {
                let key = self.key.clone();
                match current_transaction {
                    Some(txn) => {
                        match event {
                            DocEvent::UpdateV1 => txn.unobserve_update_v1(key),
                            DocEvent::UpdateV2 => txn.unobserve_update_v2(key),
                            DocEvent::Subdocs => txn.unobserve_subdocs(key),
                        };
                        true
                    }
                    None => match event {
                        DocEvent::UpdateV1 => doc.unobserve_update_v1(key).is_ok(),
                        DocEvent::UpdateV2 => doc.unobserve_update_v2(key).is_ok(),
                        DocEvent::Subdocs => doc.unobserve_subdocs(key).is_ok(),
                    },
                }
            }
            // The branch may have been deleted (and garbage collected), so it has to be
            // resolved through a transaction before its observer can be removed.
            Target::Branch { doc, unobserve } => match current_transaction {
                Some(txn) => {
                    unobserve(&ReadTransaction::ReadWrite(txn));
                    true
                }
                None => doc
                    .readonly(None, |txn| {
                        unobserve(txn);
                        Ok(())
                    })
                    .is_ok(),
            },
            Target::Awareness { awareness, event } => {
                let mut awareness = awareness.0.lock().unwrap_or_else(|err| err.into_inner());
                match event {
                    AwarenessEvent::Update => awareness.unobserve_update(self.key.clone()),
                    AwarenessEvent::Change => awareness.unobserve_change(self.key.clone()),
                };
                true
            }
        };
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.unsubscribe(None);
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
