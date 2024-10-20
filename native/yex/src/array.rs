use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::{
    atoms,
    doc::{DocResource, TransactionResource},
    shared_type::{NifSharedType, SharedTypeId},
    yinput::NifYInput,
    youtput::NifYOut,
    NifAny,
};

pub type ArrayRefId = SharedTypeId<ArrayRef>;

#[derive(NifStruct)]
#[module = "Yex.Array"]
pub struct NifArray {
    doc: ResourceArc<DocResource>,
    reference: ArrayRefId,
}

impl NifArray {
    pub fn new(doc: ResourceArc<DocResource>, array: ArrayRef) -> Self {
        NifArray {
            doc,
            reference: ArrayRefId::new(array.hook()),
        }
    }
}
impl NifSharedType for NifArray {
    type RefType = ArrayRef;

    fn doc(&self) -> &ResourceArc<DocResource> {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
    const DELETED_ERROR: &'static str = "Array has been deleted";
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifYInput,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        array.insert(txn, index, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_insert_list(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    values: Vec<NifAny>,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        array.insert_range(txn, index, values.into_iter().map(|a| a.0.clone()));
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_length(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array.len(txn))
    })
}
#[rustler::nif]
fn array_get(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = array.doc();
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        array
            .get(txn, index)
            .map(|b| (atoms::ok(), NifYOut::from_native(b, doc.clone())))
            .ok_or(rustler::Error::Atom("error"))
    })
}
#[rustler::nif]
fn array_delete_range(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    length: u32,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        array.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_to_list(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    let doc = array.doc();
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array
            .iter(txn)
            .map(|b| NifYOut::from_native(b, doc.clone()))
            .collect())
    })
}
#[rustler::nif]
fn array_to_json(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifAny> {
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array.to_json(txn).into())
    })
}
