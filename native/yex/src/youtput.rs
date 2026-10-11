use crate::{
    any::NifAny,
    doc::NifDoc,
    xml::{NifXmlElement, NifXmlFragment, NifXmlText},
    NifArray, NifMap, NifText, NifUndefinedRef, NifWeakLink,
};
use rustler::NifUntaggedEnum;

#[derive(NifUntaggedEnum)]
pub enum NifYOut {
    Any(NifAny),
    YText(NifText),
    YArray(NifArray),
    YMap(NifMap),
    YXmlElement(NifXmlElement),
    YXmlFragment(NifXmlFragment),
    YXmlText(NifXmlText),
    YDoc(NifDoc),
    YWeakLink(NifWeakLink),
    UndefinedRef(NifUndefinedRef),
}

impl NifYOut {
    /// `doc` is cloned only for shared types, so plain values cost no reference count update.
    pub fn from_native(v: yrs::Out, doc: &NifDoc) -> Self {
        match v {
            yrs::Out::Any(any) => NifYOut::Any(any.into()),
            yrs::Out::YText(text) => NifYOut::YText(NifText::new(doc.clone(), text)),
            yrs::Out::YArray(array) => NifYOut::YArray(NifArray::new(doc.clone(), array)),
            yrs::Out::YMap(map) => NifYOut::YMap(NifMap::new(doc.clone(), map)),
            yrs::Out::YXmlElement(xml) => {
                NifYOut::YXmlElement(NifXmlElement::new(doc.clone(), xml))
            }
            yrs::Out::YXmlFragment(xml) => {
                NifYOut::YXmlFragment(NifXmlFragment::new(doc.clone(), xml))
            }
            yrs::Out::YXmlText(xml) => NifYOut::YXmlText(NifXmlText::new(doc.clone(), xml)),
            yrs::Out::YWeakLink(weak) => NifYOut::YWeakLink(NifWeakLink::new(doc.clone(), weak)),
            yrs::Out::YDoc(subdoc) => NifYOut::YDoc(doc.with_cached_subdoc(subdoc, None)),
            yrs::Out::UndefinedRef(_) => {
                NifYOut::UndefinedRef(NifUndefinedRef { doc: doc.clone() })
            }
        }
    }
    pub fn from_xml_out(v: yrs::XmlOut, doc: NifDoc) -> Self {
        match v {
            yrs::XmlOut::Element(xml) => NifYOut::YXmlElement(NifXmlElement::new(doc, xml)),
            yrs::XmlOut::Fragment(xml) => NifYOut::YXmlFragment(NifXmlFragment::new(doc, xml)),
            yrs::XmlOut::Text(xml) => NifYOut::YXmlText(NifXmlText::new(doc, xml)),
        }
    }
}
