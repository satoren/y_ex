use std::sync::RwLock;
use yrs::{ReadTxn, Store, Transaction, TransactionMut};

pub struct TransactionResource(pub RwLock<Option<TransactionMut<'static>>>);

#[rustler::resource_impl]
impl rustler::Resource for TransactionResource {}

unsafe impl Send for TransactionResource {}
unsafe impl Sync for TransactionResource {}

// A transaction dropped without commit_transaction (e.g. its owner crashed) must still
// give undo managers parked behind it a chance to be released.
impl Drop for TransactionResource {
    fn drop(&mut self) {
        let txn = self.0.get_mut().unwrap_or_else(|e| e.into_inner());
        *txn = None;
        crate::undo::release_parked_undo_managers();
    }
}

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
