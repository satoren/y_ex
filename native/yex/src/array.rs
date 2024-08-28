use std::ops::Deref;

use rustler::{Env, NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::{
    doc::{DocResource, TransactionResource},
    error::NifError,
    wrap::NifWrap,
    yinput::NifYInput,
    youtput::NifYOut,
    NifAny,
};

pub type ArrayRefResource = NifWrap<ArrayRef>;
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
            reference: ResourceArc::new(array.into()),
        }
    }
}

impl Deref for NifArray {
    type Target = ArrayRef;
    fn deref(&self) -> &Self::Target {
        &self.reference.0
    }
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifYInput,
) -> Result<(), NifError> {
    array.doc.mutably(env, current_transaction, |txn| {
        array.reference.insert(txn, index, value);
        Ok(())
    })
}
#[rustler::nif]
fn array_length(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> u32 {
    array
        .doc
        .readonly(current_transaction, |txn| array.reference.len(txn))
}
#[rustler::nif]
fn array_get(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> Result<NifYOut, ()> {
    array.doc.readonly(current_transaction, |txn| {
        array
            .reference
            .get(txn, index)
            .map(|b| NifYOut::from_native(b, array.doc.clone()))
            .ok_or(())
    })
}
#[rustler::nif]
fn array_delete_range(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    length: u32,
) -> Result<(), NifError> {
    array.doc.mutably(env, current_transaction, |txn| {
        array.reference.remove_range(txn, index, length);
        Ok(())
    })
}
#[rustler::nif]
fn array_to_list(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Vec<NifYOut> {
    array.doc.readonly(current_transaction, |txn| {
        array
            .reference
            .iter(txn)
            .map(|b| NifYOut::from_native(b, array.doc.clone()))
            .collect()
    })
}
#[rustler::nif]
fn array_to_json(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifAny {
    array.doc.readonly(current_transaction, |txn| {
        array.reference.to_json(txn).into()
    })
}
