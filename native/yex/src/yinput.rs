use std::collections::HashMap;

use crate::{
    any::{NifAny, NifAttr},
    array::NifArray,
    atoms,
    doc::{try_parent_doc, NifDoc},
    error::ArgumentError,
    map::NifMap,
    text::NifText,
    weak::NifWeakLink,
    wrap::NifWrap,
    xml::{NifXmlElement, NifXmlFragment, NifXmlText},
};
use rustler::*;
use yrs::{
    block::{ItemContent, Prelim, Unused},
    branch::{Branch, BranchPtr},
    types::{xml::XmlPrelim, Delta, TypeRef},
    Any, Array, ArrayRef, Doc, Map, MapRef, ReadTxn, Text, TextRef, TransactionMut, WeakPrelim,
    Xml, XmlElementRef, XmlFragment, XmlFragmentRef, XmlTextRef,
};

#[derive(NifStruct)]
#[module = "Yex.ArrayPrelim"]
pub struct NifArrayPrelim {
    list: Vec<NifYInput>,
}

#[derive(NifStruct)]
#[module = "Yex.MapPrelim"]
pub struct NifMapPrelim {
    map: HashMap<String, NifYInput>,
}

#[derive(NifStruct)]
#[module = "Yex.TextPrelim"]
pub struct NifTextPrelim {
    delta: NifYInputDelta,
}

#[derive(NifStruct)]
#[module = "Yex.XmlFragmentPrelim"]
pub struct NifXmlFragmentPrelim {
    children: Vec<NifXmlIn>,
}

impl XmlPrelim for NifXmlFragmentPrelim {}
impl Prelim for NifXmlFragmentPrelim {
    type Return = XmlFragmentRef;

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        let inner = Branch::new(TypeRef::XmlFragment);
        (ItemContent::Type(inner), Some(self))
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        let xml = XmlFragmentRef::from(inner_ref);
        for value in self.children {
            xml.push_back(txn, value);
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlElementPrelim"]
pub struct NifXmlElementPrelim {
    tag: String,
    attributes: HashMap<String, NifYInput>,
    children: Vec<NifXmlIn>,
}
impl XmlPrelim for NifXmlElementPrelim {}

impl Prelim for NifXmlElementPrelim {
    type Return = XmlElementRef;

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        let inner = Branch::new(TypeRef::XmlElement(self.tag.clone().into()));
        (ItemContent::Type(inner), Some(self))
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        let xml = XmlElementRef::from(inner_ref);
        for (key, value) in self.attributes {
            xml.insert_attribute(txn, key, value);
        }
        for value in self.children {
            xml.push_back(txn, value);
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlTextPrelim"]
pub struct NifXmlTextPrelim {
    attributes: HashMap<String, NifYInput>,
    delta: NifYInputDelta,
}

impl XmlPrelim for NifXmlTextPrelim {}
impl Prelim for NifXmlTextPrelim {
    type Return = XmlTextRef;

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        (ItemContent::Type(Branch::new(TypeRef::XmlText)), Some(self))
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        let text_ref = XmlTextRef::from(inner_ref);
        for (key, value) in self.attributes {
            text_ref.insert_attribute(txn, key, value);
        }
        text_ref.apply_delta(txn, self.delta.0);
    }
}

pub type WeakPrelimResource = NifWrap<WeakPrelim<BranchPtr>>;

#[rustler::resource_impl]
impl rustler::Resource for WeakPrelimResource {}

#[derive(NifStruct)]
#[module = "Yex.WeakPrelim"]
pub struct NifWeakPrelim {
    reference: ResourceArc<WeakPrelimResource>,
}

impl NifWeakPrelim {
    pub fn new(weak: WeakPrelim<BranchPtr>) -> NifWeakPrelim {
        NifWeakPrelim {
            reference: ResourceArc::new(weak.into()),
        }
    }
}

pub enum NifYInput {
    Any(NifAny),
    MapPrelim(NifMapPrelim),
    ArrayPrelim(NifArrayPrelim),
    TextPrelim(NifTextPrelim),
    XmlTextPrelim(NifXmlTextPrelim),
    XmlElementPrelim(NifXmlElementPrelim),
    XmlFragmentPrelim(NifXmlFragmentPrelim),
    WeakPrelim(NifWeakPrelim),
    Doc(NifDoc),
}

// Written by hand instead of derived with NifUntaggedEnum, which turns every variant's
// error into `invalid_variant`: a document that cannot be inserted has to raise its own
// error. Variants are tried in the order the derive used.
impl<'a> Decoder<'a> for NifYInput {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        if let Ok(v) = NifAny::decode(term) {
            return Ok(NifYInput::Any(v));
        }
        if let Ok(v) = NifMapPrelim::decode(term) {
            return Ok(NifYInput::MapPrelim(v));
        }
        if let Ok(v) = NifArrayPrelim::decode(term) {
            return Ok(NifYInput::ArrayPrelim(v));
        }
        if let Ok(v) = NifTextPrelim::decode(term) {
            return Ok(NifYInput::TextPrelim(v));
        }
        if let Ok(v) = NifXmlTextPrelim::decode(term) {
            return Ok(NifYInput::XmlTextPrelim(v));
        }
        if let Ok(v) = NifXmlElementPrelim::decode(term) {
            return Ok(NifYInput::XmlElementPrelim(v));
        }
        if let Ok(v) = NifXmlFragmentPrelim::decode(term) {
            return Ok(NifYInput::XmlFragmentPrelim(v));
        }
        if let Ok(v) = NifWeakPrelim::decode(term) {
            return Ok(NifYInput::WeakPrelim(v));
        }
        if let Ok(doc) = NifDoc::decode(term) {
            // A document can be integrated into one parent only. Fails instead of blocking
            // when the document has an open transaction.
            if try_parent_doc(&doc)?.is_some() {
                return Err(ArgumentError::raise(
                    "document is already a subdocument; create a second Yex.Doc with the same guid",
                ));
            }
            return Ok(NifYInput::Doc(doc));
        }
        Err(Error::RaiseAtom("invalid_variant"))
    }
}

impl Encoder for NifYInput {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            NifYInput::Any(v) => v.encode(env),
            NifYInput::MapPrelim(v) => v.encode(env),
            NifYInput::ArrayPrelim(v) => v.encode(env),
            NifYInput::TextPrelim(v) => v.encode(env),
            NifYInput::XmlTextPrelim(v) => v.encode(env),
            NifYInput::XmlElementPrelim(v) => v.encode(env),
            NifYInput::XmlFragmentPrelim(v) => v.encode(env),
            NifYInput::WeakPrelim(v) => v.encode(env),
            NifYInput::Doc(v) => v.encode(env),
        }
    }
}

impl NifYInput {
    /// Raises ArgumentError when the input is a document that cannot be inserted into the
    /// document of `txn`. Call it before inserting, since into_content can only panic.
    pub fn ensure_insertable(&self, txn: &TransactionMut) -> NifResult<()> {
        match self {
            NifYInput::Doc(doc) => match doc_insert_error(&doc.reference.doc, txn) {
                Some(reason) => Err(ArgumentError::raise(reason)),
                None => Ok(()),
            },
            _ => Ok(()),
        }
    }
}

/// Returns why `inserted` cannot be inserted into the document of `txn`, if it cannot.
///
/// Decoding already rejected a document that is a subdocument. Inserting a document into
/// itself or into one of its own subdocuments would deadlock (the latter on the next
/// Doc.destroy). The walk up the parents stops at an ancestor whose store is locked, so it
/// is best effort: with root -> middle -> leaf and another process holding a transaction on
/// middle, inserting root into leaf is not detected. It also stops when it revisits a
/// document, so an existing cycle elsewhere cannot make it loop.
fn doc_insert_error(inserted: &Doc, txn: &TransactionMut) -> Option<&'static str> {
    if Doc::ptr_eq(inserted, txn.doc()) {
        return Some("cannot insert a document into itself");
    }
    let mut ancestor = txn.parent_doc();
    let mut seen = vec![txn.doc().clone()];
    while let Some(d) = ancestor {
        if Doc::ptr_eq(inserted, &d) {
            return Some("cannot insert a document into one of its own subdocuments");
        }
        if seen.iter().any(|s| Doc::ptr_eq(s, &d)) {
            break; // an existing cycle that does not pass through the inserted document
        }
        ancestor = yrs::Transact::try_transact(&d)
            .ok()
            .and_then(|t| t.parent_doc());
        seen.push(d);
    }
    None
}

//Array(ArrayPrelim),
//Map(MapPrelim),
//XmlElement(XmlElementPrelim),
//XmlFragment(XmlFragmentPrelim),
//XmlText(XmlDeltaPrelim),
//Doc(Doc),
//#[cfg(feature = "weak")]
//WeakLink(crate::types::weak::WeakPrelim<BranchPtr>),

impl Prelim for NifYInput {
    type Return = Unused;

    fn into_content(self, txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        match self {
            NifYInput::Any(any) => {
                let value: Any = any.0;
                (ItemContent::Any(vec![value]), None)
            }
            NifYInput::MapPrelim(_) => {
                let inner = Branch::new(TypeRef::Map);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::ArrayPrelim(_) => {
                let inner = Branch::new(TypeRef::Array);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::TextPrelim(_) => {
                let inner = Branch::new(TypeRef::Text);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::XmlTextPrelim(_) => {
                let inner = Branch::new(TypeRef::XmlText);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::XmlElementPrelim(ref v) => {
                let inner = Branch::new(TypeRef::XmlElement(v.tag.clone().into()));
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::XmlFragmentPrelim(_) => {
                let inner = Branch::new(TypeRef::XmlFragment);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::WeakPrelim(ref v) => {
                let link_source = v.reference.0.source().clone();
                let inner = Branch::new(TypeRef::WeakLink(link_source));
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::Doc(doc) => {
                // The NIFs call ensure_insertable first and raise ArgumentError. This is a
                // backstop for a caller that does not: into_content cannot return an error,
                // and integrating the document would deadlock.
                if let Some(reason) = doc_insert_error(&doc.reference.doc, txn) {
                    panic!("{reason}");
                }
                (ItemContent::Doc(None, doc.reference.doc.clone()), None)
            }
        }
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        match self {
            NifYInput::Any(any) => {
                let any = any.0;
                any.integrate(txn, inner_ref);
            }
            NifYInput::MapPrelim(v) => {
                let map = MapRef::from(inner_ref);
                for (key, value) in v.map {
                    map.insert(txn, key, value);
                }
            }
            NifYInput::ArrayPrelim(v) => {
                let array = ArrayRef::from(inner_ref);
                for value in v.list {
                    array.push_back(txn, value);
                }
            }
            NifYInput::TextPrelim(v) => {
                let text = TextRef::from(inner_ref);
                text.apply_delta(txn, v.delta.0);
            }
            NifYInput::XmlTextPrelim(v) => v.integrate(txn, inner_ref),
            NifYInput::XmlElementPrelim(v) => v.integrate(txn, inner_ref),
            NifYInput::XmlFragmentPrelim(v) => v.integrate(txn, inner_ref),
            NifYInput::WeakPrelim(_) => {}
            NifYInput::Doc(doc) => {
                let doc = doc.reference.doc.clone();
                doc.integrate(txn, inner_ref);
            }
        }
    }
}

#[derive(NifUntaggedEnum)]
pub enum NifXmlIn {
    Text(NifXmlTextPrelim),
    Element(NifXmlElementPrelim),
    Fragment(NifXmlFragmentPrelim),
}

impl XmlPrelim for NifXmlIn {}

impl Prelim for NifXmlIn {
    type Return = Unused;

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        match self {
            NifXmlIn::Text(_) => {
                let inner = Branch::new(TypeRef::XmlText);
                (ItemContent::Type(inner), Some(self))
            }
            NifXmlIn::Element(ref v) => {
                let inner = Branch::new(TypeRef::XmlElement(v.tag.clone().into()));
                (ItemContent::Type(inner), Some(self))
            }
            NifXmlIn::Fragment(_) => {
                let inner = Branch::new(TypeRef::XmlFragment);
                (ItemContent::Type(inner), Some(self))
            }
        }
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        match self {
            NifXmlIn::Text(v) => v.integrate(txn, inner_ref),
            NifXmlIn::Element(v) => v.integrate(txn, inner_ref),
            NifXmlIn::Fragment(v) => v.integrate(txn, inner_ref),
        }
    }
}

pub type NifYInputDelta = NifWrap<Vec<Delta<NifYInput>>>;

impl NifYInputDelta {
    /// Calls [NifYInput::ensure_insertable] on every inserted value.
    pub fn ensure_insertable(&self, txn: &TransactionMut) -> NifResult<()> {
        for delta in self.iter() {
            if let Delta::Inserted(value, _) = delta {
                value.ensure_insertable(txn)?;
            }
        }
        Ok(())
    }
}

impl<'a> Decoder<'a> for NifYInputDelta {
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
    let attributes = term
        .map_get(atoms::attributes())
        .or_else(|_| term.map_get("attributes"));

    if let Ok(insert) = term
        .map_get(atoms::insert())
        .or_else(|_| term.map_get("insert"))
    {
        let attrs = attributes.map_or(None, |s| {
            s.decode()
                .map_or(None, |attr: NifAttr| Some(Box::new(attr.0)))
        });
        return Ok(Delta::Inserted(insert.decode::<NifYInput>()?, attrs));
    }
    if let Ok(delete) = term
        .map_get(atoms::delete())
        .or_else(|_| term.map_get("delete"))
    {
        if let Ok(len) = delete.decode::<u32>() {
            return Ok(Delta::Deleted(len));
        }
    }
    if let Ok(retain) = term
        .map_get(atoms::retain())
        .or_else(|_| term.map_get("retain"))
    {
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

fn encode_delta<'a>(env: Env<'a>, delta: &Delta<NifYInput>) -> Term<'a> {
    let mut map = Term::map_new(env);
    match delta {
        Delta::Inserted(value, attrs) => {
            map = map.map_put(atoms::insert(), value.encode(env)).unwrap();
            if let Some(attrs) = attrs {
                map = map
                    .map_put(
                        atoms::attributes(),
                        NifAttr::from(attrs.as_ref().clone()).encode(env),
                    )
                    .unwrap();
            }
        }
        Delta::Deleted(len) => {
            map = map.map_put(atoms::delete(), len.encode(env)).unwrap();
        }
        Delta::Retain(len, attrs) => {
            map = map.map_put(atoms::retain(), len.encode(env)).unwrap();
            if let Some(attrs) = attrs {
                map = map
                    .map_put(
                        atoms::attributes(),
                        NifAttr::from(attrs.as_ref().clone()).encode(env),
                    )
                    .unwrap();
            }
        }
    }
    map
}
impl rustler::Encoder for NifYInputDelta {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let deltas: Vec<Term<'b>> = self
            .iter()
            .map(|delta| encode_delta(env, delta))
            .collect::<Vec<Term<'b>>>();
        deltas.encode(env)
    }
}

#[derive(NifUntaggedEnum)]
pub enum NifSharedTypeInput {
    Text(NifText),
    Map(NifMap),
    Array(NifArray),
    XmlText(NifXmlText),
    XmlElement(NifXmlElement),
    XmlFragment(NifXmlFragment),
    WeakLink(NifWeakLink),
}

/// Matches a `NifSharedTypeInput`, binds the inner shared type of every variant to
/// `$t` and evaluates `$body` for it. A new variant goes here and every dispatch site
/// built on this macro picks it up.
macro_rules! with_shared_type {
    ($input:expr, $t:ident => $body:expr) => {
        match $input {
            $crate::yinput::NifSharedTypeInput::Text($t) => $body,
            $crate::yinput::NifSharedTypeInput::Map($t) => $body,
            $crate::yinput::NifSharedTypeInput::Array($t) => $body,
            $crate::yinput::NifSharedTypeInput::XmlText($t) => $body,
            $crate::yinput::NifSharedTypeInput::XmlElement($t) => $body,
            $crate::yinput::NifSharedTypeInput::XmlFragment($t) => $body,
            $crate::yinput::NifSharedTypeInput::WeakLink($t) => $body,
        }
    };
}
pub(crate) use with_shared_type;
