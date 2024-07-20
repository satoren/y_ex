use std::ops::Deref;

use rustler::{NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::atoms;
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
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.insert(txn, index, input);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            self.reference.insert(&mut txn, index, input);
            Ok(())
        }
    }
    pub fn length(&self) -> u32 {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.len(txn)
        } else {
            let txn = self.doc.0.doc.transact();

            self.reference.len(&txn)
        }
    }
    pub fn delete_range(&self, index: u32, length: u32) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.remove_range(txn, index, length);
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            self.reference.remove_range(&mut txn, index, length);
        }
        Ok(())
    }
    pub fn get(&self, index: u32) -> Result<NifYOut, NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            let doc = self.doc.clone();
            self.reference
                .get(txn, index)
                .map(|b| NifYOut::from_native(b, doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        } else {
            let txn = self.doc.0.doc.transact();

            let doc = self.doc.clone();
            self.reference
                .get(&txn, index)
                .map(|b| NifYOut::from_native(b, doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        }
    }
    pub fn to_list(&self) -> Vec<NifYOut> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            let doc = self.doc.clone();
            self.reference
                .iter(txn)
                .map(|b| NifYOut::from_native(b, doc.clone()))
                .collect()
        } else {
            let txn = self.doc.0.doc.transact();
            let doc = self.doc.clone();
            self.reference
                .iter(&txn)
                .map(|b| NifYOut::from_native(b, doc.clone()))
                .collect()
        }
    }
    pub fn to_json(&self) -> NifAny {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.to_json(txn).into()
        } else {
            let txn = self.doc.0.doc.transact();
            self.reference.to_json(&txn).into()
        }
    }
}

impl Deref for NifArray {
    type Target = ArrayRef;
    fn deref(&self) -> &Self::Target {
        &self.reference.0
    }
}
