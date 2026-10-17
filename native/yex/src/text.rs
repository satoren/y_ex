use crate::{
    any::{encode as encode_any, encode_str},
    utils::{capped_index_and_length, normalize_index_for_insert},
    wrap::{make_map, NifStr},
    yinput::NifWeakPrelim,
};
use rustler::{Atom, Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use types::text::{Diff, YChange};
use yrs::*;

use crate::{
    any::NifAttr,
    atoms,
    doc::NifDoc,
    event::{NifSharedTypeDeepObservable, NifSharedTypeObservable, NifTextEvent},
    shared_type::{NifSharedType, SharedTypeId},
    transaction::TransactionResource,
    yinput::{NifYInput, NifYInputDelta},
    youtput::NifYOut,
};

pub type TextRefId = SharedTypeId<TextRef>;

#[derive(NifStruct)]
#[module = "Yex.Text"]
pub struct NifText {
    doc: NifDoc,
    reference: TextRefId,
}
impl NifText {
    pub fn new(doc: NifDoc, text: TextRef) -> Self {
        NifText {
            doc,
            reference: TextRefId::new(text.hook()),
        }
    }
}

impl NifSharedType for NifText {
    type RefType = TextRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }

    const DELETED_ERROR: &'static str = "Text has been deleted";
}
impl NifSharedTypeDeepObservable for NifText {}
impl NifSharedTypeObservable for NifText {
    type Event = NifTextEvent;
}

#[rustler::nif]
fn text_insert(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    chunk: &str,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        let index = normalize_index_for_insert(text.len(txn), index);
        text.insert(txn, index, chunk);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_insert_with_attributes(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    chunk: &str,
    attr: NifAttr,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        let index = normalize_index_for_insert(text.len(txn), index);
        text.insert_with_attributes(txn, index, chunk, attr.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_insert_embed(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    embed: NifYInput,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        embed.ensure_insertable(txn)?;
        let index = normalize_index_for_insert(text.len(txn), index);
        let mut delta = Vec::with_capacity(2);
        if index > 0 {
            delta.push(yrs::types::Delta::Retain(index, None));
        }
        delta.push(yrs::types::Delta::Inserted(embed, None));
        text.apply_delta(txn, delta);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_insert_embed_with_attributes(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    embed: NifYInput,
    attr: NifAttr,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        embed.ensure_insertable(txn)?;
        let index = normalize_index_for_insert(text.len(txn), index);
        let mut delta = Vec::with_capacity(2);
        if index > 0 {
            delta.push(yrs::types::Delta::Retain(index, None));
        }
        delta.push(yrs::types::Delta::Inserted(embed, Some(Box::new(attr.0))));
        text.apply_delta(txn, delta);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_delete(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    len: u32,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        let capped_len = capped_index_and_length(text.len(txn), index, len);

        if let Some((index, len)) = capped_len {
            text.remove_range(txn, index, len);
        }
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_format(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    len: u32,
    attr: NifAttr,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        let capped_len = capped_index_and_length(text.len(txn), index, len);

        if let Some((index, len)) = capped_len {
            text.format(txn, index, len, attr.0);
        }
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn text_to_string(
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifStr<String>> {
    text.readonly(current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        Ok(NifStr(text.get_string(txn)))
    })
}
#[rustler::nif]
fn text_length(
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    text.readonly(current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        Ok(text.len(txn))
    })
}

#[rustler::nif]
fn text_to_delta(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<rustler::Term<'_>> {
    let diff = text.readonly(
        current_transaction,
        |txn| -> Result<Vec<Diff<YChange>>, rustler::Error> {
            let text = text.get_ref(txn)?;
            Ok(text.diff(txn, YChange::identity))
        },
    )?;
    encode_diffs(diff, &text.doc, env)
}

#[rustler::nif]
fn text_quote(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    len: u32,
) -> NifResult<NifWeakPrelim> {
    text.mutably(env, current_transaction, |txn| {
        let text_ref = text.get_ref(txn)?;
        let capped_len = capped_index_and_length(text_ref.len(txn), index, len);

        if let Some((index, len)) = capped_len {
            if let Ok(quote) = text_ref.quote(txn, index..index + len) {
                let weak = NifWeakPrelim::new(quote.upcast());
                return Ok(weak);
            }
        }

        Err(rustler::Error::Term(Box::new(atoms::out_of_bounds())))
    })
}

#[rustler::nif]
fn text_apply_delta(
    env: Env<'_>,
    text: NifText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    delta: NifYInputDelta,
) -> NifResult<Atom> {
    text.mutably(env, current_transaction, |txn| {
        let text = text.get_ref(txn)?;
        delta.ensure_insertable(txn)?;
        text.apply_delta(txn, delta.0);
        Ok(atoms::ok())
    })
}

pub fn encode_diffs<'a>(
    diff: Vec<Diff<YChange>>,
    doc: &NifDoc,
    env: Env<'a>,
) -> NifResult<Term<'a>> {
    let deltas: Vec<Term<'a>> = diff
        .iter()
        .map(|diff| encode_diff(diff, doc, env))
        .collect::<Result<Vec<Term<'a>>, rustler::Error>>()?;
    Ok(deltas.encode(env))
}
pub fn encode_diff<'a>(diff: &Diff<YChange>, doc: &NifDoc, env: Env<'a>) -> NifResult<Term<'a>> {
    let insert = NifYOut::from_native(diff.insert.clone(), doc).encode(env);

    let ychange = diff.ychange.as_ref().map(|ychange| {
        let kind = match ychange.kind {
            types::text::ChangeKind::Added => "added",
            types::text::ChangeKind::Removed => "removed",
        };
        make_map(env, [(encode_str(env, "kind"), encode_str(env, kind))])
    });
    let attributes = match (diff.attributes.as_deref(), ychange) {
        (None, None) => None,
        (attrs, ychange) => {
            // ychange replaces a formatting attribute of the same name.
            let has_ychange = ychange.is_some();
            let attrs = attrs
                .into_iter()
                .flatten()
                .filter(move |(k, _)| !has_ychange || k.as_ref() != "ychange");
            let attrs = attrs.map(|(k, v)| (encode_str(env, k), encode_any(env, v)));
            let ychange = ychange.map(|ychange| (encode_str(env, "ychange"), ychange));
            Some(make_map(env, attrs.chain(ychange)))
        }
    };

    let insert = (atoms::insert().encode(env), insert);
    let attributes = attributes.map(|attrs| (atoms::attributes().encode(env), attrs));
    Ok(make_map(env, std::iter::once(insert).chain(attributes)))
}
