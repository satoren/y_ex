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
/// Serialize the given map to a JSON value.
///
/// The function performs a read-only transaction and returns the map encoded as JSON.
///
/// # Parameters
///
/// - `current_transaction`: optional transaction resource to use; if `None`, a read-only transaction is created.
///
/// # Returns
///
/// A JSON representation of the map as a NIF term.
///
/// # Examples
///
/// ```
/// // `map` is a `NifMap` obtained from the surrounding NIF context.
/// let json_term = map_to_json(map, None).unwrap();
/// // `json_term` now contains the map encoded as JSON (as a `NifAny`).
/// ```
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
/// Returns all keys stored in the map.
///
/// Performs the operation inside the provided read transaction or opens a read transaction when `None`.
///
/// # Returns
/// A vector containing each map key as a `String`.
///
/// # Examples
///
/// ```no_run
/// # use yex::map::map_keys;
/// # use yex::types::NifMap;
/// # use rustler::ResourceArc;
/// # use yex::transaction::TransactionResource;
/// # let map: NifMap = unimplemented!();
/// let keys = map_keys(map, None).unwrap();
/// ```
#[rustler::nif]
fn map_keys(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<String>> {
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        Ok(map.keys(txn).map(String::from).collect())
    })
}
/// Return all values stored in the map as `NifYOut`, using the map's document for conversion.
///
/// The result is a `Vec<NifYOut>` containing every value from the map. Any nested vectors produced
/// by the underlying `values()` iterator are flattened so the returned vector is a single-level list.
///
/// # Examples
///
/// ```
/// // assume `map` is a `NifMap` and `txn_res` is an optional TransactionResource
/// let values: Vec<NifYOut> = map_values(map, None).unwrap();
/// assert!(values.iter().all(|v| matches!(v, NifYOut::Y(..) | NifYOut::Scalar(..))));
/// ```
#[rustler::nif]
fn map_values(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    let doc = map.doc();
    map.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;
        // idk why values() returns Iterator<Item = Vec<Out>>
        Ok(map
            .values(txn)
            .flatten()
            .map(|v| NifYOut::from_native(v, doc.clone()))
            .collect())
    })
}