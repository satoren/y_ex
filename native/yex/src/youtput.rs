use crate::{
    any::NifAny, doc::NifDoc, DocResource, NifArray, NifMap, NifText, NifUndefinedRef, NifWeakLink,
    NifXmlElement, NifXmlFragment, NifXmlText,
};
use rustler::{NifUntaggedEnum, ResourceArc};

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
    pub fn from_native(v: yrs::Out, doc: ResourceArc<DocResource>) -> Self {
        match v {
            yrs::Out::Any(any) => NifYOut::Any(any.into()),
            yrs::Out::YText(text) => NifYOut::YText(NifText::new(doc, text)),
            yrs::Out::YArray(array) => NifYOut::YArray(NifArray::new(doc, array)),
            yrs::Out::YMap(map) => NifYOut::YMap(NifMap::new(doc, map)),
            yrs::Out::YXmlElement(_) => NifYOut::YXmlElement(NifXmlElement { doc }),
            yrs::Out::YXmlFragment(_) => NifYOut::YXmlFragment(NifXmlFragment {}),
            yrs::Out::YXmlText(_) => NifYOut::YXmlText(NifXmlText { doc }),
            yrs::Out::YDoc(doc) => NifYOut::YDoc(NifDoc::from_native(doc)),
            yrs::Out::UndefinedRef(_) => NifYOut::UndefinedRef(NifUndefinedRef { doc }),
        }
    }
}
