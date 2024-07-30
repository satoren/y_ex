use std::collections::HashMap;

use rustler::{Decoder, Encoder, Env, ListIterator, NifResult, NifStruct, ResourceArc, Term};
use types::{
    text::{Diff, YChange},
    Delta,
};
use yrs::*;

use crate::{
    any::NifAttr, doc::DocResource, error::NifError, wrap::NifWrap, yinput::NifYInput,
    youtput::NifYOut, ENV,
};

pub type TextReResource = NifWrap<TextRef>;
#[rustler::resource_impl]
impl rustler::Resource for TextReResource {}

#[derive(NifStruct)]
#[module = "Yex.Text"]
pub struct NifText {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<TextReResource>,
}
impl NifText {
    pub fn new(doc: ResourceArc<DocResource>, text: TextRef) -> Self {
        NifText {
            doc,
            reference: ResourceArc::new(text.into()),
        }
    }

    pub fn insert(&self, index: u32, chunk: &str) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.insert(txn, index, chunk);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            self.reference.insert(&mut txn, index, chunk);
            Ok(())
        }
    }

    pub fn insert_with_attributes(
        &self,
        index: u32,
        chunk: &str,
        attr: NifAttr,
    ) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference
                .insert_with_attributes(txn, index, chunk, attr.0);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            self.reference
                .insert_with_attributes(&mut txn, index, chunk, attr.0);
            Ok(())
        }
    }

    pub fn delete(&self, index: u32, len: u32) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.remove_range(txn, index, len);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            self.reference.remove_range(&mut txn, index, len);
            Ok(())
        }
    }

    pub fn format(&self, index: u32, len: u32, attr: NifAttr) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.format(txn, index, len, attr.0);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();
            self.reference.format(&mut txn, index, len, attr.0);
            Ok(())
        }
    }

    pub fn length(&self) -> u32 {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.len(txn)
        } else {
            let txn = self.doc.0.doc.transact();

            self.reference.len(&txn)
        }
    }
    pub fn diff(&self) -> Vec<Diff<YChange>> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.diff(txn, YChange::identity)
        } else {
            let txn = self.doc.0.doc.transact();

            self.reference.diff(&txn, YChange::identity)
        }
    }

    pub fn apply_delta(&self, delta: Vec<Delta<NifYInput>>) -> Result<(), NifError> {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            self.reference.apply_delta(txn, delta);
            Ok(())
        } else {
            let mut txn = self.doc.0.doc.transact_mut();

            self.reference.apply_delta(&mut txn, delta);
            Ok(())
        }
    }
}

impl std::fmt::Display for NifText {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        if let Some(txn) = self.doc.current_transaction.borrow_mut().as_mut() {
            write!(f, "{}", self.reference.get_string(txn))
        } else {
            let txn = self.doc.0.doc.transact();

            write!(f, "{}", self.reference.get_string(&txn))
        }
    }
}

#[rustler::nif]
fn text_insert(env: Env<'_>, text: NifText, index: u32, chunk: &str) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.insert(index, chunk))
}

#[rustler::nif]
fn text_insert_with_attributes(
    env: Env<'_>,
    text: NifText,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        text.insert_with_attributes(index, chunk, attr)
    })
}

#[rustler::nif]
fn text_delete(env: Env<'_>, text: NifText, index: u32, len: u32) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.delete(index, len))
}

#[rustler::nif]
fn text_format(
    env: Env<'_>,
    text: NifText,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.format(index, len, attr))
}

#[rustler::nif]
fn text_to_string(text: NifText) -> String {
    text.to_string()
}
#[rustler::nif]
fn text_length(text: NifText) -> u32 {
    text.length()
}

#[rustler::nif]
fn text_to_delta(env: Env<'_>, text: NifText) -> NifResult<rustler::Term<'_>> {
    let diff = text.diff();
    encode_diffs(diff, &text.doc, env)
}

#[rustler::nif]
fn text_apply_delta(text: NifText, delta: NifInDelta) -> Result<(), NifError> {
    text.apply_delta(delta.0)
}

type NifInDelta = NifWrap<Vec<Delta<NifYInput>>>;

impl<'a> Decoder<'a> for NifInDelta {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        if let Ok(v) = term.decode::<ListIterator<'a>>() {
            let a = v
                .map(|v| decode_delta(v))
                .collect::<Result<Vec<Delta<NifYInput>>, rustler::Error>>()?;

            return Ok(a.into());
        }
        Err(rustler::Error::BadArg)
    }
}

fn decode_delta(term: Term<'_>) -> NifResult<Delta<NifYInput>> {
    let attributes = term.map_get("attributes");

    if let Ok(insert) = term.map_get("insert") {
        let attrs = attributes.map_or(None, |s| {
            s.decode()
                .map_or(None, |attr: NifAttr| Some(Box::new(attr.0)))
        });
        return Ok(Delta::Inserted(insert.decode::<NifYInput>()?, attrs));
    }
    if let Ok(delete) = term.map_get("delete") {
        if let Ok(len) = delete.decode::<u32>() {
            return Ok(Delta::Deleted(len));
        }
    }
    if let Ok(retain) = term.map_get("retain") {
        if let Ok(len) = retain.decode::<u32>() {
            let attrs = attributes.map_or(None, |s| {
                s.decode()
                    .map_or(None, |attr: NifAttr| Some(Box::new(attr.0)))
            });
            return Ok(Delta::Retain(len, attrs));
        }
    }
    Err(rustler::Error::BadArg)
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
    let mut result: HashMap<String, NifYOut> = HashMap::from([("insert".into(), insert)]);

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

    if let Some(attribute) = attribute {
        result.insert(
            "attributes".into(),
            NifYOut::Any(Any::from(attribute).into()),
        );
    }

    Ok(result.encode(env))
}
