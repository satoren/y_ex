use crate::atoms;
use crate::doc::TransactionResource;
use crate::shared_type::{NifSharedType, SharedTypeId};
use crate::{doc::DocResource, yinput::NifYInput, youtput::NifYOut, NifAny};
use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::collections::HashMap;
use yrs::types::ToJson;
use yrs::*;

pub type MapRefId = SharedTypeId<MapRef>;
#[derive(NifStruct)]
#[module = "Yex.Map"]
pub struct NifMap {
    doc: ResourceArc<DocResource>,
    reference: MapRefId,
}
impl NifMap {
    pub fn new(doc: ResourceArc<DocResource>, map: MapRef) -> Self {
        NifMap {
            doc,
            reference: MapRefId::new(map.hook()),
        }
    }
}

impl NifSharedType for NifMap {
    type RefType = MapRef;

    fn doc(&self) -> &ResourceArc<DocResource> {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
    const DELETED_ERROR: &'static str = "Map has been deleted";
}

#[rustler::nif]
fn map_set(
    env: Env<'_>,
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
    value: NifYInput,
) -> NifResult<Atom> {
    map.mutably(env, current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        map.insert(txn, key, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn map_size(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        Ok(map.len(txn))
    })
}
#[rustler::nif]
fn map_get(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<(Atom, NifYOut)> {
    let doc = map.doc();
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
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
    map.mutably(env, current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        map.remove(txn, key);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn map_to_map(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<HashMap<String, NifYOut>> {
    let doc = map.doc();
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
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
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        Ok(map.to_json(txn).into())
    })
}
