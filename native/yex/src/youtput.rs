use crate::{
    any::NifAny, doc::NifDoc, DocResource, NifArray, NifMap, NifText, NifUndefinedRef, NifWeakLink,
    NifXmlElement, NifXmlFragment, NifXmlText,
};
use rustler::{NifUntaggedEnum, ResourceArc};
use yrs::Value;

#[derive(NifUntaggedEnum)]
pub enum NifValue {
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

impl NifValue {
    pub fn from_native(v: Value, doc: ResourceArc<DocResource>) -> Self {
        match v {
            yrs::Value::Any(any) => NifValue::Any(any.into()),
            yrs::Value::YText(text) => NifValue::YText(NifText::new(doc, text)),
            yrs::Value::YArray(array) => NifValue::YArray(NifArray::new(doc, array)),
            yrs::Value::YMap(map) => NifValue::YMap(NifMap::new(doc, map)),
            yrs::Value::YXmlElement(_) => NifValue::YXmlElement(NifXmlElement { doc: doc }),
            yrs::Value::YXmlFragment(_) => NifValue::YXmlFragment(NifXmlFragment {}),
            yrs::Value::YXmlText(_) => NifValue::YXmlText(NifXmlText { doc: doc }),
            yrs::Value::YDoc(doc) => NifValue::YDoc(NifDoc::from_native(doc)),
            yrs::Value::UndefinedRef(_) => NifValue::UndefinedRef(NifUndefinedRef { doc: doc }),
        }
    }
}
