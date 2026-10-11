use rustler::{Decoder, Encoder, Env, NifException, NifResult, ResourceArc, Term};
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
// Hooks go through postcard rather than a self-describing format: they are decoded on every
// call on a shared type and encoded on every one that returns one. Nested hooks and typical
// root names fit the stack buffer, so encoding allocates only the result binary.
impl<T> Encoder for SharedTypeId<T> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut buf = [0u8; 64];
        match postcard::to_slice(&self.hook, &mut buf) {
            Ok(bytes) => SliceIntoBinary::new(bytes).encode(env),
            Err(_) => {
                let bytes = postcard::to_allocvec(&self.hook).expect("encode failed");
                SliceIntoBinary::new(&bytes).encode(env)
            }
        }
    }
}
impl<'a, T: 'a> Decoder<'a> for SharedTypeId<T> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        match postcard::take_from_bytes::<Hook<T>>(bin.as_slice()) {
            Ok((hook, [])) => Ok(SharedTypeId::new(hook)),
            _ => Err(rustler::Error::BadArg),
        }
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
