use rustler::{Decoder, Encoder, Env, ListIterator, NifResult, NifStruct, NifUntaggedEnum, ResourceArc, Term};
use yrs::types::{array::ArrayEvent, map::MapEvent, text::TextEvent, xml::{XmlEvent, XmlTextEvent}, Delta};

use crate::{array::NifArray, doc::DocResource, map::NifMap, text::NifText, wrap::NifWrap, xml::{NifXmlFragment, NifXmlText}, youtput::NifYOut};

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
#[derive(NifUntaggedEnum)]
pub enum NifPath {
    Path(Vec<PathSegment>),
}
impl From<yrs::types::Path> for NifPath {
    #[inline]
    fn from(value: yrs::types::Path) -> Self {
        NifPath::Path(value.into_iter().map(|segment| segment.into()).collect())
    }
}


#[derive(NifStruct)]
#[module = "Yex.ArrayEvent"]
pub struct NifArrayEvent {
    pub path: NifPath,
    pub target: NifArray,
}

impl NifArrayEvent {
    pub fn new(doc: ResourceArc<DocResource>, event: &ArrayEvent) -> Self {
        NifArrayEvent {
            path: event
                .path().into(),
            target: NifArray::new(doc, event.target().clone()),
        }
    }
}



#[derive(NifStruct)]
#[module = "Yex.TextEvent"]
pub struct NifTextEvent {
    pub path: NifPath,
    pub target: NifText,
}

impl NifTextEvent {
    pub fn new(doc: ResourceArc<DocResource>, event: &TextEvent) -> Self {
        NifTextEvent {
            path: event
            .path().into(),
            target: NifText::new(doc, event.target().clone()),
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
    pub fn new(doc: ResourceArc<DocResource>, event: &MapEvent) -> Self {
        NifMapEvent {
            path: event
            .path().into(),
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
    pub fn new(doc: ResourceArc<DocResource>, event: &XmlEvent) -> Self {
        NifXmlEvent {
            path: event
            .path().into(),
            target: NifYOut::from_xml_out( event.target().clone(), doc),
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
    pub fn new(doc: ResourceArc<DocResource>, event: &XmlTextEvent) -> Self {
        NifXmlTextEvent {
            path: event
            .path().into(),
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
    pub fn new(doc: ResourceArc<DocResource>, event: & yrs::types::Event) -> Self {
        match event {
            yrs::types::Event::Text(event) => NifEvent::Text(NifTextEvent::new(doc, &event)),
            yrs::types::Event::Array(event) => NifEvent::Array(NifArrayEvent::new(doc, &event)),
            yrs::types::Event::Map(event) => NifEvent::Map(NifMapEvent::new(doc, &event)),
            yrs::types::Event::XmlFragment(event) => NifEvent::XmlFragment(NifXmlEvent::new(doc, &event)),
            yrs::types::Event::XmlText(event) => NifEvent::XmlText(NifXmlTextEvent::new(doc, &event)),
        }
    }
}