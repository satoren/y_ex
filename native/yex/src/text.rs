use std::collections::HashMap;

use rustler::{Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use types::{
    text::{Diff, YChange},
    Delta,
};
use yrs::*;

use crate::{
    any::NifAttr,
    atoms,
    doc::DocResource,
    error::NifError,
    wrap::NifWrap,
    yinput::{NifYInput, NifYInputDelta},
    youtput::NifYOut,
    ENV,
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
        self.doc.mutably(|txn| {
            self.reference.insert(txn, index, chunk);
            Ok(())
        })
    }

    pub fn insert_with_attributes(
        &self,
        index: u32,
        chunk: &str,
        attr: NifAttr,
    ) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference
                .insert_with_attributes(txn, index, chunk, attr.0);
            Ok(())
        })
    }

    pub fn delete(&self, index: u32, len: u32) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.remove_range(txn, index, len);
            Ok(())
        })
    }

    pub fn format(&self, index: u32, len: u32, attr: NifAttr) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.format(txn, index, len, attr.0);
            Ok(())
        })
    }

    pub fn length(&self) -> u32 {
        self.doc.readonly(|txn| self.reference.len(txn))
    }
    pub fn diff(&self) -> Vec<Diff<YChange>> {
        self.doc
            .readonly(|txn| self.reference.diff(txn, YChange::identity))
    }

    pub fn apply_delta(&self, delta: Vec<Delta<NifYInput>>) -> Result<(), NifError> {
        self.doc.mutably(|txn| {
            self.reference.apply_delta(txn, delta);
            Ok(())
        })
    }
}

impl std::fmt::Display for NifText {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.doc
            .readonly(|txn| write!(f, "{}", self.reference.get_string(txn)))
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
fn text_apply_delta(text: NifText, delta: NifYInputDelta) -> Result<(), NifError> {
    text.apply_delta(delta.0)
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
