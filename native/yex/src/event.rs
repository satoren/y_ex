use std::collections::HashMap;

use rustler::{Env, NifStruct, NifUntaggedEnum, ResourceArc, Term};
use yrs::{
    types::{
        array::ArrayEvent,
        map::MapEvent,
        text::TextEvent,
        xml::{XmlEvent, XmlTextEvent},
        Change, Delta,
    },
    TransactionMut,
};

use crate::{
    any::NifAny, array::NifArray, atoms, doc::DocResource, map::NifMap, text::NifText,
    wrap::NifWrap, xml::NifXmlText, youtput::NifYOut,
};

#[derive(NifUntaggedEnum)]
pub enum PathSegment {
    /// Key segments are used to inform how to access child shared collections within a [Map] types.
    Key(String),

    /// Index segments are used to inform how to access child shared collections within an [Array]
    /// or [XmlElement] types.
    Index(u32),
}

impl From<yrs::types::PathSegment> for PathSegment {
    #[inline]
    fn from(value: yrs::types::PathSegment) -> Self {
        match value {
            yrs::types::PathSegment::Key(key) => PathSegment::Key(key.to_string()),
            yrs::types::PathSegment::Index(index) => PathSegment::Index(index),
        }
    }
}

type NifPath = NifWrap<yrs::types::Path>;

impl rustler::Encoder for NifPath {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let segments: Vec<Term> = self
            .0
            .iter()
            .map(|segment| match segment {
                yrs::types::PathSegment::Key(key) => key.encode(env),
                yrs::types::PathSegment::Index(index) => index.encode(env),
            })
            .collect();
        segments.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifPath {
    fn decode(term: Term<'a>) -> rustler::NifResult<Self> {
        let segments: Vec<Term> = term.decode()?;
        let path = segments
            .iter()
            .map(|segment| {
                if let Ok(key) = segment.decode::<&str>() {
                    Ok(yrs::types::PathSegment::Key(key.into()))
                } else if let Ok(index) = segment.decode::<u32>() {
                    Ok(yrs::types::PathSegment::Index(index))
                } else {
                    Err(rustler::Error::BadArg)
                }
            })
            .collect::<Result<Vec<yrs::types::PathSegment>, rustler::Error>>()?;
        Ok(NifWrap(yrs::types::Path::from(path)))
    }
}

pub struct NifYArrayChange {
    doc: ResourceArc<DocResource>,
    change: Vec<yrs::types::Change>,
}

impl rustler::Encoder for NifYArrayChange {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: Vec<Term<'_>> = self
            .change
            .clone()
            .into_iter()
            .map(|change| match change {
                Change::Added(content) => {
                    let content: Vec<Term<'_>> = content
                        .into_iter()
                        .map(|item| NifYOut::from_native(item, self.doc.clone()).encode(env))
                        .collect();

                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::insert(), content).unwrap();
                    map
                }
                Change::Removed(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::delete(), index).unwrap();
                    map
                }
                Change::Retain(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::retain(), index).unwrap();
                    map
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYArrayChange {
    fn decode(term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

#[derive(NifStruct)]
#[module = "Yex.ArrayEvent"]
pub struct NifArrayEvent {
    pub path: NifPath,
    pub target: NifArray,
    pub change: NifYArrayChange,
}

impl NifArrayEvent {
    pub fn new(
        doc: &ResourceArc<DocResource>,
        event: &ArrayEvent,
        txn: &TransactionMut<'_>,
    ) -> Self {
        NifArrayEvent {
            path: event.path().into(),
            target: NifArray::new(doc.clone(), event.target().clone()),
            change: NifYArrayChange {
                doc: doc.clone(),
                change: event.delta(txn).to_vec(),
            },
        }
    }
}

pub struct NifYTextDelta {
    doc: ResourceArc<DocResource>,
    delta: Vec<yrs::types::Delta>,
}

impl rustler::Encoder for NifYTextDelta {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: Vec<Term<'_>> = self
            .delta
            .clone()
            .into_iter()
            .map(|change| match change {
                Delta::Inserted(content, attr) => {
                    let insert = NifYOut::from_native(content, self.doc.clone());

                    let attribute = attr.map(|attr| {
                        attr.iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<HashMap<String, NifAny>>()
                    });

                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::insert(), insert).unwrap();
                    map = map.map_put(atoms::attributes(), attribute).unwrap();
                    map
                }
                Delta::Deleted(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::delete(), index).unwrap();
                    map
                }
                Delta::Retain(index, attr) => {
                    let attribute = attr.map(|attr| {
                        attr.iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<HashMap<String, NifAny>>()
                    });
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::retain(), index).unwrap();
                    map = map.map_put(atoms::attributes(), attribute).unwrap();
                    map
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYTextDelta {
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

#[derive(NifStruct)]
#[module = "Yex.TextEvent"]
pub struct NifTextEvent {
    pub path: NifPath,
    pub target: NifText,
    pub delta: NifYTextDelta,
}

impl NifTextEvent {
    pub fn new(
        doc: &ResourceArc<DocResource>,
        event: &TextEvent,
        txn: &TransactionMut<'_>,
    ) -> Self {
        NifTextEvent {
            path: event.path().into(),
            target: NifText::new(doc.clone(), event.target().clone()),
            delta: NifYTextDelta {
                doc: doc.clone(),
                delta: event.delta(txn).to_vec(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.MapEvent"]
pub struct NifMapEvent {
    pub path: NifPath,
    pub target: NifMap,
}

impl NifMapEvent {
    pub fn new(doc: ResourceArc<DocResource>, event: &MapEvent, txn: &TransactionMut<'_>) -> Self {
        NifMapEvent {
            path: event.path().into(),
            target: NifMap::new(doc, event.target().clone()),
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlEvent"]
pub struct NifXmlEvent {
    pub path: NifPath,
    pub target: NifYOut, // XmlFragment or XmlText or XmlElement
}

impl NifXmlEvent {
    pub fn new(doc: ResourceArc<DocResource>, event: &XmlEvent, txn: &TransactionMut<'_>) -> Self {
        NifXmlEvent {
            path: event.path().into(),
            target: NifYOut::from_xml_out(event.target().clone(), doc),
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlTextEvent"]
pub struct NifXmlTextEvent {
    pub path: NifPath,
    pub target: NifXmlText,
}

impl NifXmlTextEvent {
    pub fn new(
        doc: ResourceArc<DocResource>,
        event: &XmlTextEvent,
        txn: &TransactionMut<'_>,
    ) -> Self {
        NifXmlTextEvent {
            path: event.path().into(),
            target: NifXmlText::new(doc, event.target().clone()),
        }
    }
}

#[derive(NifUntaggedEnum)]
pub enum NifEvent {
    Text(NifTextEvent),
    Array(NifArrayEvent),
    Map(NifMapEvent),
    XmlFragment(NifXmlEvent),
    XmlText(NifXmlTextEvent),
}

impl NifEvent {
    pub fn new(
        doc: ResourceArc<DocResource>,
        event: &yrs::types::Event,
        txn: &TransactionMut<'_>,
    ) -> Self {
        match event {
            yrs::types::Event::Text(event) => NifEvent::Text(NifTextEvent::new(&doc, &event, txn)),
            yrs::types::Event::Array(event) => {
                NifEvent::Array(NifArrayEvent::new(&doc, &event, txn))
            }
            yrs::types::Event::Map(event) => NifEvent::Map(NifMapEvent::new(doc, &event, txn)),
            yrs::types::Event::XmlFragment(event) => {
                NifEvent::XmlFragment(NifXmlEvent::new(doc, &event, txn))
            }
            yrs::types::Event::XmlText(event) => {
                NifEvent::XmlText(NifXmlTextEvent::new(doc, &event, txn))
            }
        }
    }
}
