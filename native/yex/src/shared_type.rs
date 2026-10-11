use rustler::{Decoder, Encoder, Env, NifException, NifResult, ResourceArc, Term};
use std::ops::Deref;
use yrs::block::ClientID;
use yrs::branch::BranchID;
use yrs::{Hook, ReadTxn, SharedRef, TransactionMut, ID};

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
// The hook is encoded by hand rather than through serde: it is decoded on every call on a
// shared type and encoded on every one that returns one.
// Nested: [0, client: u64 LE, clock: u32 LE]. Root: [1, name as UTF-8].
const NESTED_TAG: u8 = 0;
const ROOT_TAG: u8 = 1;

impl<T> Encoder for SharedTypeId<T> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        match self.hook.id() {
            BranchID::Nested(id) => {
                let mut bytes = [0u8; 13];
                bytes[0] = NESTED_TAG;
                bytes[1..9].copy_from_slice(&id.client.get().to_le_bytes());
                bytes[9..13].copy_from_slice(&id.clock.to_le_bytes());
                SliceIntoBinary::new(&bytes).encode(env)
            }
            BranchID::Root(name) => {
                let mut bin = rustler::NewBinary::new(env, name.len() + 1);
                let bytes = bin.as_mut_slice();
                bytes[0] = ROOT_TAG;
                bytes[1..].copy_from_slice(name.as_bytes());
                bin.into()
            }
        }
    }
}
impl<'a, T: 'a> Decoder<'a> for SharedTypeId<T> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        let id = match bin.as_slice() {
            [NESTED_TAG, rest @ ..] if rest.len() == 12 => {
                let client = u64::from_le_bytes(rest[0..8].try_into().unwrap());
                let clock = u32::from_le_bytes(rest[8..12].try_into().unwrap());
                if client >= 1 << 53 {
                    return Err(rustler::Error::BadArg);
                }
                BranchID::Nested(ID::new(ClientID::new(client), clock))
            }
            [ROOT_TAG, name @ ..] => BranchID::Root(
                std::str::from_utf8(name)
                    .map_err(|_| rustler::Error::BadArg)?
                    .into(),
            ),
            _ => return Err(rustler::Error::BadArg),
        };
        Ok(SharedTypeId::new(Hook::from(id)))
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
