use rustler::{NifStruct, ResourceArc};
use yrs::*;

use crate::{any::NifAttr, doc::DocResource, error::NifError, wrap::NifWrap};

pub type TextReResource = NifWrap<TextRef>;
#[rustler::resource_impl]
impl rustler::Resource for TextReResource {}

#[derive(NifStruct)]
#[module = "Yex.Text"]
pub struct NifText {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<TextReResource>,
}
impl NifText {
    pub fn new(doc: ResourceArc<DocResource>, text: TextRef) -> Self {
        NifText {
            doc: doc,
            reference: ResourceArc::new(text.into()),
        }
    }

    pub fn insert(&self, index: u32, chunk: &str) -> Result<(), NifError> {
        if let Some(mut txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            Ok(self.reference.insert(&mut txn, index, chunk))
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            Ok(self.reference.insert(&mut txn, index, chunk))
        }
    }

    pub fn insert_with_attributes(
        &self,
        index: u32,
        chunk: &str,
        attr: NifAttr,
    ) -> Result<(), NifError> {
        if let Some(mut txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            Ok(self
                .reference
                .insert_with_attributes(&mut txn, index, chunk, attr.0))
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            Ok(self
                .reference
                .insert_with_attributes(&mut txn, index, chunk, attr.0))
        }
    }

    pub fn delete(&self, index: u32, len: u32) -> Result<(), NifError> {
        if let Some(mut txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            Ok(self.reference.remove_range(&mut txn, index, len))
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            Ok(self.reference.remove_range(&mut txn, index, len))
        }
    }

    pub fn format(&self, index: u32, len: u32, attr: NifAttr) -> Result<(), NifError> {
        if let Some(mut txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            Ok(self.reference.format(&mut txn, index, len, attr.0))
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            Ok(self.reference.format(&mut txn, index, len, attr.0))
        }
    }

    pub fn to_string(&self) -> String {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.get_string(txn)
        } else {
            let txn = self.doc.0.doc.transact();

            self.reference.get_string(&txn)
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
}
