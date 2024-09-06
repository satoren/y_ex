use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::{
    atoms,
    doc::{DocResource, TransactionResource},
    error::deleted_error,
    wrap::NifWrap,
    yinput::NifYInput,
    youtput::NifYOut,
    NifAny,
};

pub type ArrayRefResource = NifWrap<Hook<ArrayRef>>;
#[rustler::resource_impl]
impl rustler::Resource for ArrayRefResource {}

#[derive(NifStruct)]
#[module = "Yex.Array"]
pub struct NifArray {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<ArrayRefResource>,
}

impl NifArray {
    pub fn new(doc: ResourceArc<DocResource>, array: ArrayRef) -> Self {
        NifArray {
            doc,
            reference: ResourceArc::new(array.hook().into()),
        }
    }
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifYInput,
) -> NifResult<Atom> {
    array.doc.mutably(env, current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        array.insert(txn, index, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_length(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    array.doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        Ok(array.len(txn))
    })
}
#[rustler::nif]
fn array_get(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
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
    let doc = array.doc;
    doc.mutably(env, current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        array.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_to_list(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
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
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        Ok(array.to_json(txn).into())
    })
}
