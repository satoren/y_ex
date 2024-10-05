use std::collections::HashMap;

use crate::{
    any::{NifAny, NifAttr},
    array::NifArray,
    atoms,
    map::NifMap,
    text::NifText,
    wrap::NifWrap,
    xml::{NifXmlElement, NifXmlFragment, NifXmlText},
};
use rustler::*;
use yrs::{
    block::{ItemContent, Prelim, Unused},
    branch::{Branch, BranchPtr},
    types::{xml::XmlPrelim, Delta, TypeRef},
    Any, Array, ArrayRef, Map, MapRef, Text, TextRef, TransactionMut, Xml, XmlElementRef,
    XmlFragment, XmlFragmentRef, XmlTextRef,
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
    attributes: HashMap<String, String>,
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
    attributes: HashMap<String, String>,
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

#[derive(NifUntaggedEnum)]
pub enum NifYInput {
    Any(NifAny),
    MapPrelim(NifMapPrelim),
    ArrayPrelim(NifArrayPrelim),
    TextPrelim(NifTextPrelim),
    XmlTextPrelim(NifXmlTextPrelim),
    XmlElementPrelim(NifXmlElementPrelim),
    XmlFragmentPrelim(NifXmlFragmentPrelim),
}

//Text(DeltaPrelim),
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

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
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
                let inner = Branch::new(TypeRef::XmlText);
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
impl<'de, 'a: 'de> rustler::Encoder for NifYInputDelta {
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
}
