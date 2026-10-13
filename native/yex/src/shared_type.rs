use rustler::{Atom, Decoder, Encoder, Env, NifException, NifResult, ResourceArc, Term};
use std::ops::Deref;
use yrs::{BranchID, Hook, Out, ReadTxn, SharedRef, TransactionMut, ID};

use crate::{
    atoms,
    doc::NifDoc,
    transaction::{ReadTransaction, TransactionResource},
    utils,
    wrap::SliceIntoBinary,
    yinput::NifSharedTypeInput,
    youtput::NifYOut,
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

/// A shared type's logical id as an Elixir term: `{:root, name}` or
/// `{:nested, client, clock}`.
pub struct NifBranchId(pub BranchID);

impl Encoder for NifBranchId {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match &self.0 {
            BranchID::Root(name) => (atoms::root(), name.as_ref()).encode(env),
            BranchID::Nested(id) => (atoms::nested(), id.client.get(), id.clock).encode(env),
        }
    }
}

impl<'a> Decoder<'a> for NifBranchId {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        if let Ok((tag, name)) = term.decode::<(Atom, &str)>() {
            if tag == atoms::root() {
                return Ok(NifBranchId(BranchID::Root(name.into())));
            }
        }
        let (tag, client, clock): (Atom, u64, u32) = term.decode()?;
        if tag != atoms::nested() {
            return Err(rustler::Error::BadArg);
        }
        Ok(NifBranchId(BranchID::Nested(ID::new(
            utils::client_id(client)?,
            clock,
        ))))
    }
}

#[rustler::nif]
fn shared_type_branch_id(shared_type: NifSharedTypeInput) -> NifBranchId {
    NifBranchId(shared_type.doc_and_id().1.clone())
}

#[rustler::nif]
fn shared_type_alive(
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<bool> {
    let (doc, id) = shared_type.doc_and_id();
    doc.readonly(current_transaction, |txn| {
        Ok(id.get_branch(txn).is_some_and(|b| !b.is_deleted()))
    })
}

/// Finds the live shared type `id` names. A deleted type is garbage collected when
/// the deleting transaction commits, so a nested id with no branch is reported as
/// deleted when the state vector shows the doc has integrated it.
#[rustler::nif]
fn shared_type_resolve(
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    id: NifBranchId,
) -> NifResult<Result<NifYOut, Atom>> {
    doc.readonly(current_transaction, |txn| {
        Ok(match id.0.get_branch(txn) {
            Some(branch) if branch.is_deleted() => Err(atoms::deleted()),
            Some(branch) => match branch.into() {
                // A root waits for a typed getter to claim it. A nested branch has a
                // type yrs maps to no struct (such as an XmlHook), so no getter helps.
                Out::UndefinedRef(_) => Err(match &id.0 {
                    BranchID::Root(_) => atoms::untyped(),
                    BranchID::Nested(_) => atoms::unsupported(),
                }),
                out => Ok(NifYOut::from_native(out, &doc)),
            },
            // The state vector stops at the first skipped range, so a type integrated
            // past a gap, then deleted and collected, reports not_found. yrs 0.28 has no
            // public per-client clock that honours skips (BlockStore is pub(crate), and
            // its get_clock ignores skips), so this builds the state vector on a miss.
            None => match &id.0 {
                BranchID::Nested(nid) if txn.state_vector().get(&nid.client) > nid.clock => {
                    Err(atoms::deleted())
                }
                _ => Err(atoms::not_found()),
            },
        })
    })
}
