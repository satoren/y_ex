use rustler::{Decoder, Encoder, Env, NifException, NifResult, ResourceArc, Term};
use serde::{Deserialize, Serialize};
use std::ops::Deref;
use yrs::{Hook, ReadTxn, SharedRef, TransactionMut};

use crate::{
    doc::NifDoc,
    transaction::{ReadTransaction, TransactionResource},
    wrap::SliceIntoBinary,
};

pub struct SharedTypeId<T> {
    hook: Hook<T>,
}

impl<T> std::panic::RefUnwindSafe for SharedTypeId<T> {}
impl<T> SharedTypeId<T> {
    pub fn new(v: Hook<T>) -> Self {
        Self { hook: v }
    }
}
impl<T> Deref for SharedTypeId<T> {
    type Target = Hook<T>;

    fn deref(&self) -> &Self::Target {
        &self.hook
    }
}
impl<T> Encoder for SharedTypeId<T> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut s = flexbuffers::FlexbufferSerializer::new();

        self.hook.serialize(&mut s).expect("encode failed");
        SliceIntoBinary::new(s.view()).encode(env)
    }
}
impl<'a, T: 'a> Decoder<'a> for SharedTypeId<T> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        let r =
            flexbuffers::Reader::get_root(bin.as_slice()).map_err(|_e| rustler::Error::BadArg)?;
        let hook = Hook::<T>::deserialize(r).map_err(|_e| rustler::Error::BadArg)?;
        Ok(SharedTypeId::new(hook))
    }
}

pub trait NifSharedType
where
    Self: Sized,
    Self::RefType: SharedRef,
{
    type RefType;
    const DELETED_ERROR: &'static str;

    fn doc(&self) -> &NifDoc;
    fn reference(&self) -> &SharedTypeId<Self::RefType>;

    fn get_ref<T: ReadTxn>(&self, txn: &T) -> NifResult<Self::RefType> {
        self.reference()
            .get(txn)
            .ok_or_else(|| deleted_error(Self::DELETED_ERROR))
    }

    fn mutably<F, T>(
        &self,
        env: Env<'_>,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> NifResult<T>
    where
        F: FnOnce(&mut TransactionMut<'_>) -> NifResult<T>,
    {
        self.doc().mutably(env, current_transaction, f)
    }

    fn readonly<F, T>(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> NifResult<T>
    where
        F: FnOnce(&ReadTransaction) -> NifResult<T>,
    {
        self.doc().readonly(current_transaction, f)
    }
}

#[derive(Debug, NifException)]
#[module = "Yex.DeletedSharedTypeError"]
pub struct DeletedSharedTypeError {
    message: String,
}

pub fn deleted_error(message: &str) -> rustler::Error {
    rustler::Error::RaiseTerm(Box::new(DeletedSharedTypeError {
        message: message.to_string(),
    }))
}
