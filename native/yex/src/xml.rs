use std::collections::HashMap;

use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use types::text::YChange;
use yrs::*;

use crate::{
    any::NifAttr,
    atoms,
    doc::{DocResource, TransactionResource},
    error::deleted_error,
    text::encode_diffs,
    wrap::NifWrap,
    yinput::{NifXmlIn, NifYInputDelta},
    youtput::NifYOut,
    ENV,
};

pub type XmlFragmentResource = NifWrap<Hook<XmlFragmentRef>>;
#[rustler::resource_impl]
impl rustler::Resource for XmlFragmentResource {}

pub type XmlElementResource = NifWrap<Hook<XmlElementRef>>;
#[rustler::resource_impl]
impl rustler::Resource for XmlElementResource {}

pub type XmlTextResource = NifWrap<Hook<XmlTextRef>>;
#[rustler::resource_impl]
impl rustler::Resource for XmlTextResource {}

#[derive(NifStruct)]
#[module = "Yex.XmlFragment"]
pub struct NifXmlFragment {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<XmlFragmentResource>,
}

impl NifXmlFragment {
    pub fn new(doc: ResourceArc<DocResource>, xml: XmlFragmentRef) -> Self {
        Self {
            doc,
            reference: ResourceArc::new(xml.hook().into()),
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlElement"]
pub struct NifXmlElement {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<XmlElementResource>,
}

impl NifXmlElement {
    pub fn new(doc: ResourceArc<DocResource>, xml: XmlElementRef) -> Self {
        Self {
            doc,
            reference: ResourceArc::new(xml.hook().into()),
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlText"]
pub struct NifXmlText {
    doc: ResourceArc<DocResource>,
    reference: ResourceArc<XmlTextResource>,
}

impl NifXmlText {
    pub fn new(doc: ResourceArc<DocResource>, xml: XmlTextRef) -> Self {
        Self {
            doc,
            reference: ResourceArc::new(xml.hook().into()),
        }
    }
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
        xml.doc.mutably(env, current_transaction, |txn| {
            let xml = xml
                .reference
                .get(txn)
                .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml.len(txn))
    })
}
#[rustler::nif]
fn xml_fragment_get(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.mutably(env, current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        xml.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_fragment_to_string(
    xml: NifXmlFragment,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml.get_string(txn).into())
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
        xml.doc.mutably(env, current_transaction, |txn| {
            let xml = xml
                .reference
                .get(txn)
                .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml.len(txn))
    })
}
#[rustler::nif]
fn xml_element_get(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
) -> NifResult<(Atom, NifYOut)> {
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.mutably(env, current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        xml.remove_range(txn, index, length);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_element_to_string(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.mutably(env, current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml.get_attribute(txn, key))
    })
}

#[rustler::nif]
fn xml_element_remove_attribute(
    env: Env<'_>,
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    key: &str,
) -> NifResult<Atom> {
    xml.doc.mutably(env, current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        xml.remove_attribute(txn, &key);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_element_get_attributes(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<HashMap<String, String>> {
    xml.doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml
            .attributes(txn)
            .map(|(key, value)| (key.into(), value))
            .collect())
    })
}

#[rustler::nif]
fn xml_element_next_sibling(
    xml: NifXmlElement,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_text_insert(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
) -> NifResult<Atom> {
    text.doc.mutably(env, current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        text.insert(txn, index, chunk);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_insert_with_attributes(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> NifResult<Atom> {
    text.doc.mutably(env, current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        text.insert_with_attributes(txn, index, chunk, attr.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_delete(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
) -> NifResult<Atom> {
    text.doc.mutably(env, current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        text.remove_range(txn, index, len);
        Ok(atoms::ok())
    })
}
#[rustler::nif]
fn xml_text_length(
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<u32> {
    text.doc.readonly(current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(text.len(txn))
    })
}

#[rustler::nif]
fn xml_text_format(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> NifResult<Atom> {
    text.doc.mutably(env, current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        text.format(txn, index, len, attr.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_apply_delta(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    delta: NifYInputDelta,
) -> NifResult<Atom> {
    text.doc.mutably(env, current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        text.apply_delta(txn, delta.0);
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn xml_text_next_sibling(
    xml: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
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
    let doc = xml.doc;
    doc.readonly(current_transaction, |txn| {
        let xml = xml
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(xml
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, doc.clone())))
    })
}

#[rustler::nif]
fn xml_text_to_delta(
    env: Env<'_>,
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<rustler::Term<'_>> {
    let diff = text.doc.readonly(current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(text.diff(txn, YChange::identity))
    })?;
    encode_diffs(diff, &text.doc, env)
}

#[rustler::nif]
fn xml_text_to_string(
    text: NifXmlText,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    text.doc.readonly(current_transaction, |txn| {
        let text = text
            .reference
            .get(txn)
            .ok_or(deleted_error("Xml has been deleted".to_string()))?;
        Ok(text.get_string(txn).into())
    })
}
