use std::sync::Mutex;

use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc, Term};
use yrs::types::ToJson;
use yrs::*;

use crate::{
    atoms,
    doc::{DocResource, TransactionResource},
    error::{deleted_error, NifError},
    event::{NifArrayEvent, NifEvent},
    shared_type::NifSharedType,
    subscription::SubscriptionResource,
    term_box::TermBox,
    wrap::encode_binary_slice_to_term,
    yinput::NifYInput,
    youtput::NifYOut,
    NifAny, ENV,
};

pub type ArrayRefId = NifSharedType<ArrayRef>;

#[derive(NifStruct)]
#[module = "Yex.Array"]
pub struct NifArray {
    doc: ResourceArc<DocResource>,
    reference: ArrayRefId,
}

impl NifArray {
    pub fn new(doc: ResourceArc<DocResource>, array: ArrayRef) -> Self {
        NifArray {
            doc,
            reference: ArrayRefId::new(array.hook()),
        }
    }
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifYInput,
) -> NifResult<Atom> {
    array.doc.mutably(env, current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        array.insert(txn, index, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_length(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    array.doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        Ok(array.len(txn))
    })
}
#[rustler::nif]
fn array_get(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        array
            .get(txn, index)
            .map(|b| (atoms::ok(), NifYOut::from_native(b, doc.clone())))
            .ok_or(rustler::Error::Atom("error"))
    })
}
#[rustler::nif]
fn array_delete_range(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    length: u32,
) -> NifResult<Atom> {
    let doc = array.doc;
    doc.mutably(env, current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        array.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_to_list(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        Ok(array
            .iter(txn)
            .map(|b| NifYOut::from_native(b, doc.clone()))
            .collect())
    })
}
#[rustler::nif]
fn array_to_json(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifAny> {
    let doc = array.doc;
    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;
        Ok(array.to_json(txn).into())
    })
}

#[rustler::nif]
fn array_observe(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    term: Term<'_>,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    let doc = array.doc;

    let term_value = TermBox::new(term);

    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;

        let doc_ref = doc.clone();
        let sub = array.observe(move |txn, event| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let v = term_value.get(*env);
                let _ = env.send(
                    &pid,
                    (
                        atoms::observe_event(),
                        v,
                        NifArrayEvent::new(doc_ref, event),
                        txn.origin()
                            .map(|s| encode_binary_slice_to_term(*env, s.as_ref())),
                    ),
                );
            })
        });

        Ok(ResourceArc::new(Mutex::new(Some(sub)).into()))
    })
}

#[rustler::nif]
fn array_observe_deep(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    term: Term<'_>,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    let doc = array.doc;

    let term_value = TermBox::new(term);

    doc.readonly(current_transaction, |txn| {
        let array = array
            .reference
            .get(txn)
            .ok_or(deleted_error("Array has been deleted".to_string()))?;

        let doc_ref = doc.clone();
        let sub = array.observe_deep(move |txn, events| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let v = term_value.get(*env);
                let events: Vec<NifEvent> = events
                    .iter()
                    .map(|event| NifEvent::new(doc_ref.clone(), event))
                    .collect();
                let _ = env.send(
                    &pid,
                    (
                        atoms::observe_event(),
                        v,
                        events,
                        txn.origin()
                            .map(|s| encode_binary_slice_to_term(*env, s.as_ref())),
                    ),
                );
            })
        });

        Ok(ResourceArc::new(Mutex::new(Some(sub)).into()))
    })
}
