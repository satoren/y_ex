use crate::doc::TransactionResource;
use crate::{
    doc::DocResource, error::NifError, wrap::NifWrap, yinput::NifYInput, youtput::NifYOut, NifAny,
};
use rustler::{Env, NifStruct, ResourceArc};
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
}
impl Deref for NifMap {
    type Target = MapRef;
    fn deref(&self) -> &Self::Target {
        &self.reference.0
    }
}

#[rustler::nif]
fn map_set(
    env: Env<'_>,
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
    value: NifYInput,
) -> Result<(), NifError> {
    map.doc.mutably(env, current_transaction, |txn| {
        map.reference.insert(txn, key, value);
        Ok(())
    })
}
#[rustler::nif]
fn map_size(map: NifMap, current_transaction: Option<ResourceArc<TransactionResource>>) -> u32 {
    map.doc
        .readonly(current_transaction, |txn| map.reference.len(txn))
}
#[rustler::nif]
fn map_get(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> Result<NifYOut, ()> {
    map.doc.readonly(current_transaction, |txn| {
        map.reference
            .get(txn, key)
            .map(|b| NifYOut::from_native(b, map.doc.clone()))
            .ok_or(())
    })
}
#[rustler::nif]
fn map_delete(
    env: Env<'_>,
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> Result<(), NifError> {
    map.doc.mutably(env, current_transaction, |txn| {
        map.reference.remove(txn, key);
        Ok(())
    })
}
#[rustler::nif]
fn map_to_map(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> HashMap<String, NifYOut> {
    map.doc.readonly(current_transaction, |txn| {
        map.reference
            .iter(txn)
            .map(|(key, value)| (key.into(), NifYOut::from_native(value, map.doc.clone())))
            .collect()
    })
}
#[rustler::nif]
fn map_to_json(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifAny {
    map.doc
        .readonly(current_transaction, |txn| map.reference.to_json(txn).into())
}
