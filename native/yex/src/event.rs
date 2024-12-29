use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use rustler::{Encoder, Env, NifResult, NifStruct, NifUntaggedEnum, ResourceArc, Term};
use yrs::{
    types::{
        array::ArrayEvent,
        map::MapEvent,
        text::TextEvent,
        xml::{XmlEvent, XmlTextEvent},
        Change, Delta, EntryChange,
    },
    DeepObservable, Observable, TransactionMut,
};

use crate::{
    any::NifAny, array::NifArray, atoms, doc::DocResource, map::NifMap, shared_type::NifSharedType,
    subscription::SubscriptionResource, term_box::TermBox, text::NifText,
    transaction::TransactionResource, utils::origin_to_term, wrap::NifWrap, xml::NifXmlText,
    yinput::NifSharedTypeInput, youtput::NifYOut, ENV,
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
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

pub trait NifEventConstructor<Event>
where
    Self: Sized + Encoder,
{
    fn new(doc: &ResourceArc<DocResource>, event: &Event, txn: &TransactionMut<'_>) -> Self;
}

#[derive(NifStruct)]
#[module = "Yex.ArrayEvent"]
pub struct NifArrayEvent {
    pub path: NifPath,
    pub target: NifArray,
    pub change: NifYArrayChange,
}

impl NifEventConstructor<ArrayEvent> for NifArrayEvent {
    fn new(doc: &ResourceArc<DocResource>, event: &ArrayEvent, txn: &TransactionMut<'_>) -> Self {
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

                    let mut map = Term::map_new(env).map_put(atoms::insert(), insert).unwrap();
                    if let Some(attr) = attr {
                        let attribute = attr
                            .iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<HashMap<String, NifAny>>();
                        map = map.map_put(atoms::attributes(), attribute).unwrap();
                    }
                    map
                }
                Delta::Deleted(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::delete(), index).unwrap();
                    map
                }
                Delta::Retain(index, attr) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::retain(), index).unwrap();
                    if let Some(attr) = attr {
                        let attribute = attr
                            .iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<HashMap<String, NifAny>>();
                        map = map.map_put(atoms::attributes(), attribute).unwrap();
                    }
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

impl NifEventConstructor<TextEvent> for NifTextEvent {
    fn new(doc: &ResourceArc<DocResource>, event: &TextEvent, txn: &TransactionMut<'_>) -> Self {
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

pub struct NifYMapChange {
    doc: ResourceArc<DocResource>,
    change: HashMap<Arc<str>, EntryChange>,
}

impl rustler::Encoder for NifYMapChange {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: HashMap<String, Term> = self
            .change
            .clone()
            .into_iter()
            .map(|(key, change)| match change {
                EntryChange::Inserted(content) => {
                    let content = NifYOut::from_native(content, self.doc.clone());
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::add())
                        .unwrap()
                        .map_put(atoms::new_value(), content)
                        .unwrap();
                    (key.to_string(), map)
                }
                EntryChange::Removed(old_value) => {
                    let old_value = NifYOut::from_native(old_value, self.doc.clone());
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::delete())
                        .unwrap()
                        .map_put(atoms::old_value(), old_value)
                        .unwrap();
                    (key.to_string(), map)
                }
                EntryChange::Updated(old_value, new_value) => {
                    let old_value = NifYOut::from_native(old_value, self.doc.clone());
                    let new_value = NifYOut::from_native(new_value, self.doc.clone());
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::update())
                        .unwrap()
                        .map_put(atoms::old_value(), old_value)
                        .unwrap()
                        .map_put(atoms::new_value(), new_value)
                        .unwrap();
                    (key.to_string(), map)
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYMapChange {
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

#[derive(NifStruct)]
#[module = "Yex.MapEvent"]
pub struct NifMapEvent {
    pub path: NifPath,
    pub target: NifMap,
    pub keys: NifYMapChange,
}

impl NifEventConstructor<MapEvent> for NifMapEvent {
    fn new(doc: &ResourceArc<DocResource>, event: &MapEvent, txn: &TransactionMut<'_>) -> Self {
        NifMapEvent {
            path: event.path().into(),
            target: NifMap::new(doc.clone(), event.target().clone()),
            keys: NifYMapChange {
                doc: doc.clone(),
                change: event.keys(txn).clone(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlEvent"]
pub struct NifXmlEvent {
    pub path: NifPath,
    pub target: NifYOut, // XmlFragment or XmlText or XmlElement

    pub delta: NifYArrayChange,

    pub keys: NifYMapChange,
}

impl NifEventConstructor<XmlEvent> for NifXmlEvent {
    fn new(doc: &ResourceArc<DocResource>, event: &XmlEvent, txn: &TransactionMut<'_>) -> Self {
        NifXmlEvent {
            path: event.path().into(),
            target: NifYOut::from_xml_out(event.target().clone(), doc.clone()),
            keys: NifYMapChange {
                doc: doc.clone(),
                change: event.keys(txn).clone(),
            },
            delta: NifYArrayChange {
                doc: doc.clone(),
                change: event.delta(txn).to_vec(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlTextEvent"]
pub struct NifXmlTextEvent {
    pub path: NifPath,
    pub target: NifXmlText,
    pub delta: NifYTextDelta,
}

impl NifEventConstructor<XmlTextEvent> for NifXmlTextEvent {
    fn new(doc: &ResourceArc<DocResource>, event: &XmlTextEvent, txn: &TransactionMut<'_>) -> Self {
        NifXmlTextEvent {
            path: event.path().into(),
            target: NifXmlText::new(doc.clone(), event.target().clone()),
            delta: NifYTextDelta {
                doc: doc.clone(),
                delta: event.delta(txn).to_vec(),
            },
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
            yrs::types::Event::Map(event) => NifEvent::Map(NifMapEvent::new(&doc, &event, txn)),
            yrs::types::Event::XmlFragment(event) => {
                NifEvent::XmlFragment(NifXmlEvent::new(&doc, &event, txn))
            }
            yrs::types::Event::XmlText(event) => {
                NifEvent::XmlText(NifXmlTextEvent::new(&doc, &event, txn))
            }
        }
    }
}

pub trait NifSharedTypeDeepObservable
where
    Self: NifSharedType,
    Self::RefType: DeepObservable,
{
    fn observe_deep(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        pid: rustler::LocalPid,
        ref_term: Term<'_>,
        metadata: Term<'_>,
    ) -> NifResult<ResourceArc<SubscriptionResource>> {
        let doc = self.doc();

        let ref_box = TermBox::new(ref_term);
        let metadata_box = TermBox::new(metadata);

        doc.readonly(current_transaction, |txn| {
            let ref_value = self.get_ref(txn)?;

            let doc_ref = doc.clone();
            let sub = ref_value.observe_deep(move |txn, events| {
                let doc_ref = doc_ref.clone();
                ENV.with(|env| {
                    let events: Vec<NifEvent> = events
                        .iter()
                        .map(|event| NifEvent::new(doc_ref.clone(), event, txn))
                        .collect();
                    let _ = env.send(
                        &pid,
                        (
                            atoms::observe_deep_event(),
                            ref_box.get(*env),
                            events,
                            origin_to_term(env, txn.origin()),
                            metadata_box.get(*env),
                        ),
                    );
                })
            });

            Ok(ResourceArc::new(Mutex::new(Some(sub)).into()))
        })
    }
}

pub trait NifSharedTypeObservable
where
    Self: NifSharedType,
    Self::RefType: Observable,
    yrs::types::Event: AsRef<<Self::RefType as yrs::Observable>::Event>,
    Self::Event: NifEventConstructor<<<Self as NifSharedType>::RefType as Observable>::Event>,
{
    type Event;
    fn observe(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        pid: rustler::LocalPid,
        ref_term: Term<'_>,
        metadata: Term<'_>,
    ) -> NifResult<ResourceArc<SubscriptionResource>> {
        let doc = self.doc();

        let ref_box = TermBox::new(ref_term);
        let metadata_box = TermBox::new(metadata);

        doc.readonly(current_transaction, |txn| {
            let ref_value = self.get_ref(txn)?;

            let doc_ref: ResourceArc<crate::wrap::NifWrap<crate::doc::DocInner>> = doc.clone();
            let sub = ref_value.observe(move |txn, event| {
                let doc_ref = doc_ref.clone();
                ENV.with(|env| {
                    let _ = env.send(
                        &pid,
                        (
                            atoms::observe_event(),
                            ref_box.get(*env),
                            Self::Event::new(&doc_ref, event, txn),
                            origin_to_term(env, txn.origin()),
                            metadata_box.get(*env),
                        ),
                    );
                })
            });

            Ok(SubscriptionResource::arc(sub))
        })
    }
}

#[rustler::nif]
fn shared_type_observe(
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    ref_term: Term<'_>,
    metadata: Term<'_>,
) -> NifResult<ResourceArc<SubscriptionResource>> {
    match shared_type {
        NifSharedTypeInput::Map(map) => map.observe(current_transaction, pid, ref_term, metadata),
        NifSharedTypeInput::Array(array) => {
            array.observe(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::Text(text) => {
            text.observe(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlText(xml_text) => {
            xml_text.observe(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlFragment(xml_fragment) => {
            xml_fragment.observe(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlElement(xml_element) => {
            xml_element.observe(current_transaction, pid, ref_term, metadata)
        }
    }
}

#[rustler::nif]
fn shared_type_observe_deep(
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    ref_term: Term<'_>,
    metadata: Term<'_>,
) -> NifResult<ResourceArc<SubscriptionResource>> {
    match shared_type {
        NifSharedTypeInput::Map(map) => {
            map.observe_deep(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::Array(array) => {
            array.observe_deep(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::Text(text) => {
            text.observe_deep(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlText(xml_text) => {
            xml_text.observe_deep(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlFragment(xml_fragment) => {
            xml_fragment.observe_deep(current_transaction, pid, ref_term, metadata)
        }
        NifSharedTypeInput::XmlElement(xml_element) => {
            xml_element.observe_deep(current_transaction, pid, ref_term, metadata)
        }
    }
}
