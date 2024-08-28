use std::collections::HashMap;

use rustler::{Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use types::text::{Diff, YChange};
use yrs::*;

use crate::{
    any::NifAttr,
    atoms,
    doc::{DocResource, TransactionResource},
    error::NifError,
    wrap::NifWrap,
    yinput::NifYInputDelta,
    youtput::NifYOut,
};

pub type TextRefResource = NifWrap<TextRef>;
#[rustler::resource_impl]
impl rustler::Resource for TextRefResource {}

#[derive(NifStruct)]
#[module = "Yex.Text"]
pub struct NifText {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<TextRefResource>,
}
impl NifText {
    pub fn new(doc: ResourceArc<DocResource>, text: TextRef) -> Self {
        NifText {
            doc,
            reference: ResourceArc::new(text.into()),
        }
    }
}

#[rustler::nif]
fn text_insert(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
) -> Result<(), NifError> {
    text.doc.mutably(env, current_transaction, |txn| {
        text.reference.insert(txn, index, chunk);
        Ok(())
    })
}

#[rustler::nif]
fn text_insert_with_attributes(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> Result<(), NifError> {
    text.doc.mutably(env, current_transaction, |txn| {
        text.reference
            .insert_with_attributes(txn, index, chunk, attr.0);
        Ok(())
    })
}

#[rustler::nif]
fn text_delete(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
) -> Result<(), NifError> {
    text.doc.mutably(env, current_transaction, |txn| {
        text.reference.remove_range(txn, index, len);
        Ok(())
    })
}

#[rustler::nif]
fn text_format(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> Result<(), NifError> {
    text.doc.mutably(env, current_transaction, |txn| {
        text.reference.format(txn, index, len, attr.0);
        Ok(())
    })
}

#[rustler::nif]
fn text_to_string(
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> String {
    text.doc
        .readonly(current_transaction, |txn| text.reference.get_string(txn))
}
#[rustler::nif]
fn text_length(
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> u32 {
    text.doc
        .readonly(current_transaction, |txn| text.reference.len(txn))
}

#[rustler::nif]
fn text_to_delta(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<rustler::Term<'_>> {
    let diff = text.doc.readonly(current_transaction, |txn| {
        text.reference.diff(txn, YChange::identity)
    });
    encode_diffs(diff, &text.doc, env)
}

#[rustler::nif]
fn text_apply_delta(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    delta: NifYInputDelta,
) -> Result<(), NifError> {
    text.doc.mutably(env, current_transaction, |txn| {
        text.reference.apply_delta(txn, delta.0);
        Ok(())
    })
}

pub fn encode_diffs<'a>(
    diff: Vec<Diff<YChange>>,
    doc: &ResourceArc<DocResource>,
    env: Env<'a>,
) -> NifResult<Term<'a>> {
    let deltas: Vec<Term<'a>> = diff
        .iter()
        .map(|diff| encode_diff(diff, doc, env))
        .collect::<Result<Vec<Term<'a>>, rustler::Error>>()?;
    Ok(deltas.encode(env))
}
pub fn encode_diff<'a>(
    diff: &Diff<YChange>,
    doc: &ResourceArc<DocResource>,
    env: Env<'a>,
) -> NifResult<Term<'a>> {
    let insert = NifYOut::from_native(diff.insert.clone(), doc.clone());

    let mut attribute = diff.attributes.as_deref().map(|attr| {
        attr.iter()
            .map(|(k, v)| (k.to_string(), Any::from(v.clone())))
            .collect::<HashMap<String, Any>>()
    });

    if let Some(ychange) = &diff.ychange {
        let ychange = match ychange.kind {
            types::text::ChangeKind::Added => {
                HashMap::from([("kind".into(), Any::String("added".into()))])
            }
            types::text::ChangeKind::Removed => {
                HashMap::from([("kind".into(), Any::String("removed".into()))])
            }
        };

        if let Some(mut attr) = attribute {
            attr.insert("ychange".into(), Any::from(ychange));
            attribute = Some(attr);
        } else {
            attribute = Some(HashMap::from([("ychange".into(), Any::from(ychange))]));
        }
    }

    let mut map = Term::map_new(env);

    map = map.map_put(atoms::insert(), insert.encode(env))?;
    if let Some(attrs) = attribute {
        map = map
            .map_put(atoms::attributes(), NifYOut::Any(Any::from(attrs).into()))
            .unwrap();
    }
    Ok(map)
}
