use crate::atoms;
use crate::{
    doc::DocResource, error::NifError, wrap::NifWrap, yinput::NifYInput, youtput::NifYOut, NifAny,
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
        self.doc.readonly(|txn| self.reference.len(txn))
    }

    pub fn set(&self, key: &str, input: NifYInput) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.insert(txn, key, input);
            Ok(())
        })
    }
    pub fn delete(&self, key: &str) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.remove(txn, key);
            Ok(())
        })
    }
    pub fn get(&self, key: &str) -> Result<NifYOut, NifError> {
        self.doc.readonly(|txn| {
            self.reference
                .get(txn, key)
                .map(|b| NifYOut::from_native(b, self.doc.clone()))
                .ok_or(NifError {
                    reason: atoms::error(),
                    message: "can not get".into(),
                })
        })
    }

    pub fn to_map(&self) -> HashMap<String, NifYOut> {
        self.doc.readonly(|txn| {
            self.reference
                .iter(txn)
                .map(|(key, value)| (key.into(), NifYOut::from_native(value, self.doc.clone())))
                .collect()
        })
    }
    pub fn to_json(&self) -> NifAny {
        self.doc.readonly(|txn| self.reference.to_json(txn).into())
    }
}
impl Deref for NifMap {
    type Target = MapRef;
    fn deref(&self) -> &Self::Target {
        &self.reference.0
    }
}
