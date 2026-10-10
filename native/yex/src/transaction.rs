use rustler::ResourceArc;
use std::sync::RwLock;
use yrs::{ReadTxn, Store, Transaction, TransactionMut};

use crate::doc::DocResource;

/// An open `Yex.Doc.transaction/3`. Its document is kept so that teardown work deferred
/// while the transaction was open can be carried out on commit.
pub struct TransactionResource(
    pub RwLock<Option<TransactionMut<'static>>>,
    pub(crate) ResourceArc<DocResource>,
);

#[rustler::resource_impl]
impl rustler::Resource for TransactionResource {}

/// Takes the value out of `slot`, releases the lock, then drops it. For a transaction the
/// drop is the commit; if it panics, `slot` already holds `None`, so the resource's
/// destructor cannot drop the same transaction a second time.
pub fn take_then_drop<T>(slot: &RwLock<Option<T>>) {
    let value = slot.write().unwrap_or_else(|e| e.into_inner()).take();
    drop(value);
}

unsafe impl Send for TransactionResource {}
unsafe impl Sync for TransactionResource {}

pub enum ReadTransaction<'a, 'doc> {
    ReadOnly(&'a Transaction<'doc>),
    ReadWrite(&'a TransactionMut<'doc>),
}

impl ReadTransaction<'_, '_> {
    /// Whether the doc holds more than `limit` items, counting every item ever inserted
    /// (the sum of its state vector). O(clients), so a normal-scheduler NIF can check it
    /// before doing work whose cost tracks the document. `None` means no limit.
    pub fn exceeds_item_limit(&self, limit: Option<u64>) -> bool {
        limit.is_some_and(|limit| {
            let items: u64 = self
                .state_vector()
                .iter()
                .map(|(_, clock)| u64::from(*clock))
                .sum();
            items > limit
        })
    }
}

impl ReadTxn for ReadTransaction<'_, '_> {
    fn store(&self) -> &Store {
        match &self {
            ReadTransaction::ReadOnly(txn) => txn.store(),
            ReadTransaction::ReadWrite(txn) => txn.store(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::take_then_drop;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::sync::RwLock;

    struct PanicOnDrop;

    impl Drop for PanicOnDrop {
        fn drop(&mut self) {
            panic!("commit failed");
        }
    }

    #[test]
    fn take_then_drop_leaves_none_when_the_drop_panics() {
        let slot = RwLock::new(Some(PanicOnDrop));
        let result = catch_unwind(AssertUnwindSafe(|| take_then_drop(&slot)));
        assert!(result.is_err());
        assert!(!slot.is_poisoned());
        assert!(slot.read().unwrap().is_none());
    }
}
