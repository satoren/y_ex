use crate::atoms;
use crate::doc::NifDoc;
use crate::event::{NifMapEvent, NifSharedTypeDeepObservable, NifSharedTypeObservable};
use crate::shared_type::NifSharedType;
use crate::shared_type::SharedTypeId;
use crate::transaction::TransactionResource;
use crate::{yinput::NifYInput, youtput::NifYOut, NifAny};
use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::collections::HashMap;
use yrs::types::ToJson;
use yrs::*;

pub type MapRefId = SharedTypeId<MapRef>;
#[derive(NifStruct)]
#[module = "Yex.Map"]
pub struct NifMap {
    doc: NifDoc,
    reference: MapRefId,
}
impl NifMap {
    pub fn new(doc: NifDoc, map: MapRef) -> Self {
        NifMap {
            doc,
            reference: MapRefId::new(map.hook()),
        }
    }
}

impl NifSharedType for NifMap {
    type RefType = MapRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
    const DELETED_ERROR: &'static str = "Map has been deleted";
}
impl NifSharedTypeDeepObservable for NifMap {}
impl NifSharedTypeObservable for NifMap {
    type Event = NifMapEvent;
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
fn map_contains_key(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<bool> {
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        Ok(map.contains_key(txn, key))
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
