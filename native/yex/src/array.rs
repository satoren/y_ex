use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use yrs::types::ToJson;
use yrs::*;

use crate::{
    atoms,
    doc::NifDoc,
    event::{NifArrayEvent, NifSharedTypeDeepObservable, NifSharedTypeObservable},
    shared_type::{NifSharedType, SharedTypeId},
    transaction::TransactionResource,
    utils::{capped_index_and_length, normalize_index, normalize_index_for_insert},
    yinput::{NifWeakPrelim, NifYInput},
    youtput::NifYOut,
    NifAny,
};

pub type ArrayRefId = SharedTypeId<ArrayRef>;

#[derive(NifStruct)]
#[module = "Yex.Array"]
pub struct NifArray {
    doc: NifDoc,
    reference: ArrayRefId,
}

impl NifArray {
    pub fn new(doc: NifDoc, array: ArrayRef) -> Self {
        NifArray {
            doc,
            reference: ArrayRefId::new(array.hook()),
        }
    }
}
impl NifSharedType for NifArray {
    type RefType = ArrayRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
    const DELETED_ERROR: &'static str = "Array has been deleted";
}
impl NifSharedTypeDeepObservable for NifArray {}
impl NifSharedTypeObservable for NifArray {
    type Event = NifArrayEvent;
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    value: NifYInput,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;

        let index = normalize_index_for_insert(array.len(txn), index);

        array.insert(txn, index, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_insert_list(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    values: Vec<NifAny>,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        let index = normalize_index_for_insert(array.len(txn), index);
        array.insert_range(txn, index, values.into_iter().map(|a| a.0.clone()));
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn array_insert_and_get(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    value: NifYInput,
) -> NifResult<NifYOut> {
    let doc = array.doc();
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        let index = normalize_index_for_insert(array.len(txn), index);
        array.insert(txn, index, value);
        Ok(NifYOut::from_native(
            array.get(txn, index).unwrap(),
            doc.clone(),
        ))
    })
}
#[rustler::nif]
fn array_length(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array.len(txn))
    })
}
#[rustler::nif]
fn array_get(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
) -> NifResult<(Atom, NifYOut)> {
    let doc = array.doc();
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        let index = normalize_index(array.len(txn), index);
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
    index: i64,
    length: u32,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        let capped_len = capped_index_and_length(array.len(txn), index, length);
        if let Some((index, len)) = capped_len {
            array.remove_range(txn, index, len);
        }
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn array_move_to(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    from: i64,
    to: i64,
) -> NifResult<Atom> {
    array.mutably(env, current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        let len = array.len(txn);
        let from = normalize_index(len, from);
        let to = normalize_index(len, to);
        if from >= len || to > len {
            return Err(rustler::Error::Atom("error"));
        }
        array.move_to(txn, from, to);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn array_quote(
    env: Env<'_>,
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    len: u32,
) -> NifResult<NifWeakPrelim> {
    array.mutably(env, current_transaction, |txn: &mut TransactionMut<'_>| {
        let array_ref = array.get_ref(txn)?;
        let capped_len = capped_index_and_length(array_ref.len(txn), index, len);

        if let Some((index, len)) = capped_len {
            if let Ok(quote) = array_ref.quote(txn, index..index + len) {
                let weak = NifWeakPrelim::new(quote.upcast());
                return Ok(weak);
            }
        }

        Err(rustler::Error::Term(Box::new(atoms::out_of_bounds())))
    })
}

#[rustler::nif]
fn array_to_list(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    let doc = array.doc();
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array
            .iter(txn)
            .map(|b| NifYOut::from_native(b, doc.clone()))
            .collect())
    })
}
#[rustler::nif]
fn array_slice(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    start_index: usize,
    amount: usize,
    step: usize,
) -> NifResult<Vec<NifYOut>> {
    let doc = array.doc();
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array
            .iter(txn)
            .skip(start_index)
            .take(amount)
            .step_by(step)
            .map(|b| NifYOut::from_native(b, doc.clone()))
            .collect())
    })
}

#[rustler::nif]
fn array_to_json(
    array: NifArray,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifAny> {
    array.readonly(current_transaction, |txn| {
        let array = array.get_ref(txn)?;
        Ok(array.to_json(txn).into())
    })
}
