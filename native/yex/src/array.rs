use std::ops::Deref;

use rustler::{Env, NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::{atoms, ENV};
use crate::{
    doc::DocResource, error::NifError, wrap::NifWrap, yinput::NifYInput, youtput::NifYOut, NifAny,
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

    pub fn insert(&self, index: u32, input: NifYInput) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.insert(txn, index, input);
            Ok(())
        })
    }
    pub fn length(&self) -> u32 {
        self.doc.readonly(|txn| self.reference.len(txn))
    }
    pub fn delete_range(&self, index: u32, length: u32) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.remove_range(txn, index, length);
            Ok(())
        })
    }
    pub fn get(&self, index: u32) -> Result<NifYOut, NifError> {
        self.doc.readonly(|txn| {
            self.reference
                .get(txn, index)
                .map(|b| NifYOut::from_native(b, self.doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        })
    }
    pub fn to_list(&self) -> Vec<NifYOut> {
        self.doc.readonly(|txn| {
            self.reference
                .iter(txn)
                .map(|b| NifYOut::from_native(b, self.doc.clone()))
                .collect()
        })
    }
    pub fn to_json(&self) -> NifAny {
        self.doc.readonly(|txn| self.reference.to_json(txn).into())
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
    index: u32,
    value: NifYInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || array.insert(index, value))
}
#[rustler::nif]
fn array_length(array: NifArray) -> u32 {
    array.length()
}
#[rustler::nif]
fn array_get(array: NifArray, index: u32) -> Result<NifYOut, NifError> {
    array.get(index)
}
#[rustler::nif]
fn array_delete_range(
    env: Env<'_>,
    array: NifArray,
    index: u32,
    length: u32,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || array.delete_range(index, length))
}
#[rustler::nif]
fn array_to_list(array: NifArray) -> Vec<NifYOut> {
    array.to_list()
}
#[rustler::nif]
fn array_to_json(array: NifArray) -> NifAny {
    array.to_json()
}
