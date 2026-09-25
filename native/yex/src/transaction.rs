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

impl ReadTxn for ReadTransaction<'_, '_> {
    fn store(&self) -> &Store {
        match &self {
            ReadTransaction::ReadOnly(txn) => txn.store(),
            ReadTransaction::ReadWrite(txn) => txn.store(),
        }
    }
}
