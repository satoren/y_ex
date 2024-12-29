use std::cell::RefCell;
use yrs::{ReadTxn, Store, Transaction, TransactionMut};

pub struct TransactionResource(pub RefCell<Option<TransactionMut<'static>>>);

unsafe impl Send for TransactionResource {}
unsafe impl Sync for TransactionResource {}

#[rustler::resource_impl]
impl rustler::Resource for TransactionResource {}

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
