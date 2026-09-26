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

unsafe impl Send for TransactionResource {}
unsafe impl Sync for TransactionResource {}

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
