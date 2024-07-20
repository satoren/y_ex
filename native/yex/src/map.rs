use crate::atoms;
use crate::{
    doc::DocResource, error::NifError, wrap::NifWrap, yinput::NifYInput, youtput::NifValue, NifAny,
};
use rustler::{NifStruct, ResourceArc};
use std::{collections::HashMap, ops::Deref};
use yrs::types::ToJson;
use yrs::*;

pub type MapRefResource = NifWrap<MapRef>;
#[rustler::resource_impl]
impl rustler::Resource for MapRefResource {}

#[derive(NifStruct)]
#[module = "Yex.Map"]
pub struct NifMap {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<MapRefResource>,
}
impl NifMap {
    pub fn new(doc: ResourceArc<DocResource>, map: MapRef) -> Self {
        NifMap {
            doc,
            reference: ResourceArc::new(map.into()),
        }
    }

    pub fn size(&self) -> u32 {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.len(txn)
        } else {
            let txn = self.doc.0.doc.transact();

            self.reference.len(&txn)
        }
    }

    pub fn set(&self, key: &str, input: NifYInput) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.insert(txn, key, input);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            self.reference.insert(&mut txn, key, input);
            Ok(())
        }
    }
    pub fn delete(&self, key: &str) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.remove(txn, key);
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            self.reference.remove(&mut txn, key);
        }
        Ok(())
    }
    pub fn get(&self, key: &str) -> Result<NifValue, NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            let doc = self.doc.clone();
            self.reference
                .get(txn, key)
                .map(|b| NifValue::from_native(b, doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        } else {
            let txn = self.doc.0.doc.transact();

            let doc = self.doc.clone();
            self.reference
                .get(&txn, key)
                .map(|b| NifValue::from_native(b, doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        }
    }

    pub fn to_map(&self) -> HashMap<String, NifValue> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            let doc = self.doc.clone();
            self.reference
                .iter(txn)
                .map(|(key, value)| (key.into(), NifValue::from_native(value, doc.clone())))
                .collect()
        } else {
            let txn = self.doc.0.doc.transact();
            let doc = self.doc.clone();
            self.reference
                .iter(&txn)
                .map(|(key, value)| (key.into(), NifValue::from_native(value, doc.clone())))
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
impl Deref for NifMap {
    type Target = MapRef;
    fn deref(&self) -> &Self::Target {
        &self.reference.0
    }
}
