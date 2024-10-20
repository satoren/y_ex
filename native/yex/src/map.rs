use crate::doc::TransactionResource;
use crate::event::{NifEvent, NifMapEvent};
use crate::shared_type::NifSharedType;
use crate::shared_type::SharedTypeId;
use crate::subscription::SubscriptionResource;
use crate::term_box::TermBox;
use crate::wrap::SliceIntoBinary;
use crate::{atoms, ENV};
use crate::{doc::DocResource, yinput::NifYInput, youtput::NifYOut, NifAny};
use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc, Term};
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

#[rustler::nif]
fn map_observe(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    term: Term<'_>,
) -> NifResult<ResourceArc<SubscriptionResource>> {
    let doc = map.doc();

    let term_value = TermBox::new(term);

    doc.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;

        let doc_ref = doc.clone();
        let sub = map.observe(move |txn, event| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let v = term_value.get(*env);
                let _ = env.send(
                    &pid,
                    (
                        atoms::observe_event(),
                        v,
                        NifMapEvent::new(&doc_ref, event, txn),
                        txn.origin().map(|s| SliceIntoBinary::new(s.as_ref())),
                    ),
                );
            })
        });

        Ok(SubscriptionResource::arc(sub))
    })
}

#[rustler::nif]
fn map_observe_deep(
    map: NifMap,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    term: Term<'_>,
) -> NifResult<ResourceArc<SubscriptionResource>> {
    let doc = map.doc();

    let term_value = TermBox::new(term);

    doc.readonly(current_transaction, |txn| {
        let map = map.get_ref(txn)?;

        let doc_ref = doc.clone();
        let sub = map.observe_deep(move |txn, events| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let v = term_value.get(*env);
                let events: Vec<NifEvent> = events
                    .iter()
                    .map(|event| NifEvent::new(doc_ref.clone(), event, txn))
                    .collect();
                let _ = env.send(
                    &pid,
                    (
                        atoms::observe_deep_event(),
                        v,
                        events,
                        txn.origin().map(|s| SliceIntoBinary::new(s.as_ref())),
                    ),
                );
            })
        });

        Ok(SubscriptionResource::arc(sub))
    })
}
