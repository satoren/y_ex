use std::collections::HashMap;

use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use yrs::{
    types::text::YChange, GetString, SharedRef as _, Text, Xml, XmlElementRef, XmlFragment,
    XmlFragmentRef, XmlTextRef,
};

use crate::{
    any::NifAttr,
    atoms,
    doc::NifDoc,
    event::{NifSharedTypeDeepObservable, NifSharedTypeObservable, NifXmlEvent, NifXmlTextEvent},
    shared_type::{NifSharedType, SharedTypeId},
    text::encode_diffs,
    transaction::TransactionResource,
    yinput::{NifXmlIn, NifYInputDelta},
    youtput::NifYOut,
    ENV,
};

pub type XmlFragmentId = SharedTypeId<XmlFragmentRef>;
pub type XmlElementId = SharedTypeId<XmlElementRef>;
pub type XmlTextId = SharedTypeId<XmlTextRef>;

#[derive(NifStruct)]
#[module = "Yex.XmlFragment"]
pub struct NifXmlFragment {
    doc: NifDoc,
    reference: XmlFragmentId,
}

impl NifXmlFragment {
    pub fn new(doc: NifDoc, xml: XmlFragmentRef) -> Self {
        Self {
            doc,
            reference: XmlFragmentId::new(xml.hook()),
        }
    }
}

impl NifSharedType for NifXmlFragment {
    type RefType = XmlFragmentRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }

    const DELETED_ERROR: &'static str = "XmlFragment has been deleted";
}
impl NifSharedTypeDeepObservable for NifXmlFragment {}
impl NifSharedTypeObservable for NifXmlFragment {
    type Event = NifXmlEvent;
}

#[derive(NifStruct)]
#[module = "Yex.XmlElement"]
pub struct NifXmlElement {
    doc: NifDoc,
    reference: XmlElementId,
}

impl NifXmlElement {
    pub fn new(doc: NifDoc, xml: XmlElementRef) -> Self {
        Self {
            doc,
            reference: XmlElementId::new(xml.hook()),
        }
    }
}
impl NifSharedTypeDeepObservable for NifXmlElement {}
impl NifSharedTypeObservable for NifXmlElement {
    type Event = NifXmlEvent;
}

impl NifSharedType for NifXmlElement {
    type RefType = XmlElementRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }

    const DELETED_ERROR: &'static str = "XmlElement has been deleted";
}

#[derive(NifStruct)]
#[module = "Yex.XmlText"]
pub struct NifXmlText {
    doc: NifDoc,
    reference: XmlTextId,
}

impl NifXmlText {
    pub fn new(doc: NifDoc, xml: XmlTextRef) -> Self {
        Self {
            doc,
            reference: XmlTextId::new(xml.hook()),
        }
    }
}

impl NifSharedType for NifXmlText {
    type RefType = XmlTextRef;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }

    const DELETED_ERROR: &'static str = "XmlText has been deleted";
}

impl NifSharedTypeDeepObservable for NifXmlText {}
impl NifSharedTypeObservable for NifXmlText {
    type Event = NifXmlTextEvent;
}

#[rustler::nif]
fn xml_fragment_insert(
    env: Env<'_>,
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifXmlIn,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        xml.mutably(env, current_transaction, |txn| {
            let xml = xml.get_ref(txn)?;
            xml.insert(txn, index, value);
            Ok(atoms::ok())
        })
    })
}

#[rustler::nif]
fn xml_fragment_length(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.len(txn))
    })
}
#[rustler::nif]
fn xml_fragment_get(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.get(txn, index)
            .map(|b| (atoms::ok(), NifYOut::from_xml_out(b, doc.clone())))
            .ok_or(rustler::Error::Atom("error"))
    })
}
#[rustler::nif]
fn xml_fragment_delete_range(
    env: Env<'_>,
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    length: u32,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_fragment_to_string(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.get_string(txn).into())
    })
}

#[rustler::nif]
fn xml_fragment_parent(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;

        Ok(xml.parent().map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_element_insert(
    env: Env<'_>,
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    value: NifXmlIn,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        xml.mutably(env, current_transaction, |txn| {
            let xml = xml.get_ref(txn)?;
            xml.insert(txn, index, value);
            Ok(atoms::ok())
        })
    })
}
#[rustler::nif]
fn xml_element_length(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.len(txn))
    })
}
#[rustler::nif]
fn xml_element_get(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.get(txn, index)
            .map(|b| (atoms::ok(), NifYOut::from_xml_out(b, doc.clone())))
            .ok_or(rustler::Error::Atom("error"))
    })
}
#[rustler::nif]
fn xml_element_delete_range(
    env: Env<'_>,
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    length: u32,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_element_to_string(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.get_string(txn).into())
    })
}

#[rustler::nif]
fn xml_element_insert_attribute(
    env: Env<'_>,
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
    value: &str,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.insert_attribute(txn, key, value);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn xml_element_get_attribute(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<Option<String>> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        let attr = xml.get_attribute(txn, key);
        Ok(attr)
    })
}

#[rustler::nif]
fn xml_element_remove_attribute(
    env: Env<'_>,
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.remove_attribute(txn, &key);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_element_get_attributes(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<HashMap<String, String>> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;

        let attr = xml
            .attributes(txn)
            .map(|(key, value)| (key.into(), value))
            .collect();

        Ok(attr)
    })
}

#[rustler::nif]
fn xml_element_next_sibling(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml
            .siblings(txn)
            .next()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_element_prev_sibling(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_element_parent(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;

        Ok(xml.parent().map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_text_insert(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.insert(txn, index, chunk);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_insert_with_attributes(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.insert_with_attributes(txn, index, chunk, attr.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_delete(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.remove_range(txn, index, len);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn xml_text_length(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.len(txn))
    })
}

#[rustler::nif]
fn xml_text_format(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.format(txn, index, len, attr.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_apply_delta(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    delta: NifYInputDelta,
) -> NifResult<Atom> {
    xml.mutably(env, current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        xml.apply_delta(txn, delta.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_next_sibling(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml
            .siblings(txn)
            .next()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_text_prev_sibling(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_text_to_delta(
    env: Env<'_>,
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<rustler::Term<'_>> {
    let diff = xml.readonly(current_transaction, |txn| -> Result<_, rustler::Error> {
        let xml = xml.get_ref(txn)?;
        Ok(xml.diff(txn, YChange::identity))
    })?;
    encode_diffs(diff, xml.doc(), env)
}

#[rustler::nif]
fn xml_text_to_string(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.get_string(txn).into())
    })
}

#[rustler::nif]
fn xml_text_parent(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc();
    xml.readonly(current_transaction, |txn| {
        let xml = xml.get_ref(txn)?;
        Ok(xml.parent().map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}
