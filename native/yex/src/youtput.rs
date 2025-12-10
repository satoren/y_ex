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
    pub fn from_native(v: yrs::Out, doc: NifDoc) -> Self {
        match v {
            yrs::Out::Any(any) => NifYOut::Any(any.into()),
            yrs::Out::YText(text) => NifYOut::YText(NifText::new(doc, text)),
            yrs::Out::YArray(array) => NifYOut::YArray(NifArray::new(doc, array)),
            yrs::Out::YMap(map) => NifYOut::YMap(NifMap::new(doc, map)),
            yrs::Out::YXmlElement(xml) => NifYOut::YXmlElement(NifXmlElement::new(doc, xml)),
            yrs::Out::YXmlFragment(xml) => NifYOut::YXmlFragment(NifXmlFragment::new(doc, xml)),
            yrs::Out::YXmlText(xml) => NifYOut::YXmlText(NifXmlText::new(doc, xml)),
            yrs::Out::YWeakLink(weak) => NifYOut::YWeakLink(NifWeakLink::new(doc, weak)),
            yrs::Out::YDoc(subdoc) => {
                NifYOut::YDoc(NifDoc::with_worker_pid(subdoc, doc.worker_pid))
            }
            yrs::Out::UndefinedRef(_) => NifYOut::UndefinedRef(NifUndefinedRef { doc }),
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
