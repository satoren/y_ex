use crate::atoms;
use crate::doc::TransactionResource;
use crate::error::deleted_error;
use crate::{doc::DocResource, wrap::NifWrap, yinput::NifYInput, youtput::NifYOut, NifAny};
use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::collections::HashMap;
use yrs::types::ToJson;
use yrs::*;

pub type MapRefResource = NifWrap<Hook<MapRef>>;
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
            reference: ResourceArc::new(map.hook().into()),
        }
    }
}

#[rustler::nif]
fn map_set(
    env: Env<'_>,
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
    value: NifYInput,
) -> NifResult<Atom> {
    map.doc.mutably(env, current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        map.insert(txn, key, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn map_size(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    map.doc.readonly(current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        Ok(map.len(txn))
    })
}
#[rustler::nif]
fn map_get(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<(Atom, NifYOut)> {
    let doc = map.doc;
    doc.readonly(current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        map.get(txn, key)
            .map(|b| (atoms::ok(), NifYOut::from_native(b, doc.clone())))
            .ok_or(rustler::Error::Atom("error"))
    })
}
#[rustler::nif]
fn map_delete(
    env: Env<'_>,
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<Atom> {
    map.doc.mutably(env, current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        map.remove(txn, key);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn map_to_map(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<HashMap<String, NifYOut>> {
    let doc = map.doc;
    doc.readonly(current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        Ok(map
            .iter(txn)
            .map(|(key, value)| (key.into(), NifYOut::from_native(value, doc.clone())))
            .collect())
    })
}
#[rustler::nif]
fn map_to_json(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifAny> {
    map.doc.readonly(current_transaction, |txn| {
        let map = map
            .reference
            .get(txn)
            .ok_or(deleted_error("Map has been deleted".to_string()))?;
        Ok(map.to_json(txn).into())
    })
}
