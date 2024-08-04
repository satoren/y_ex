use std::collections::HashMap;

use rustler::{Env, NifResult, NifStruct, ResourceArc};
use types::{text::YChange, xml::XmlIn};
use yrs::*;

use crate::{
    any::NifAttr,
    doc::DocResource,
    error::NifError,
    text::encode_diffs,
    wrap::NifWrap,
    yinput::{NifXmlIn, NifYInputDelta},
    youtput::NifYOut,
    ENV,
};

pub type XmlFragmentResource = NifWrap<XmlFragmentRef>;
#[rustler::resource_impl]
impl rustler::Resource for XmlFragmentResource {}

pub type XmlElementResource = NifWrap<XmlElementRef>;
#[rustler::resource_impl]
impl rustler::Resource for XmlElementResource {}

pub type XmlTextResource = NifWrap<XmlTextRef>;
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
            reference: ResourceArc::new(xml.into()),
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
            reference: ResourceArc::new(xml.into()),
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
            reference: ResourceArc::new(xml.into()),
        }
    }
}

#[rustler::nif]
fn xml_fragment_insert(
    env: Env<'_>,
    xml: NifXmlFragment,
    index: u32,
    value: NifXmlIn,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        xml.doc.mutably(env, |txn| {
            let prelim: XmlIn = value.into();
            xml.reference.insert(txn, index, prelim);
            Ok(())
        })
    })
}

#[rustler::nif]
fn xml_fragment_length(xml: NifXmlFragment) -> u32 {
    xml.doc.readonly(|txn| xml.reference.len(txn))
}
#[rustler::nif]
fn xml_fragment_get(xml: NifXmlFragment, index: u32) -> Result<NifYOut, ()> {
    xml.doc.readonly(|txn| {
        xml.reference
            .get(txn, index)
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
            .ok_or(())
    })
}
#[rustler::nif]
fn xml_fragment_delete_range(
    env: Env<'_>,
    xml: NifXmlFragment,
    index: u32,
    length: u32,
) -> Result<(), NifError> {
    xml.doc.mutably(env, |txn| {
        xml.reference.remove_range(txn, index, length);
        Ok(())
    })
}

#[rustler::nif]
fn xml_fragment_to_string(xml: NifXmlFragment) -> String {
    xml.doc.readonly(|txn| xml.reference.get_string(txn).into())
}

#[rustler::nif]
fn xml_element_insert(
    env: Env<'_>,
    xml: NifXmlElement,
    index: u32,
    value: NifXmlIn,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        xml.doc.mutably(env, |txn| {
            let prelim: XmlIn = value.into();
            xml.reference.insert(txn, index, prelim);
            Ok(())
        })
    })
}
#[rustler::nif]
fn xml_element_length(xml: NifXmlElement) -> u32 {
    xml.doc.readonly(|txn| xml.reference.len(txn))
}
#[rustler::nif]
fn xml_element_get(xml: NifXmlElement, index: u32) -> Result<NifYOut, ()> {
    xml.doc.readonly(|txn| {
        xml.reference
            .get(txn, index)
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
            .ok_or(())
    })
}
#[rustler::nif]
fn xml_element_delete_range(
    env: Env<'_>,
    xml: NifXmlElement,
    index: u32,
    length: u32,
) -> Result<(), NifError> {
    xml.doc.mutably(env, |txn| {
        xml.reference.remove_range(txn, index, length);
        Ok(())
    })
}

#[rustler::nif]
fn xml_element_to_string(xml: NifXmlElement) -> String {
    xml.doc.readonly(|txn| xml.reference.get_string(txn).into())
}

#[rustler::nif]
fn xml_element_insert_attribute(
    env: Env<'_>,
    xml: NifXmlElement,
    key: &str,
    value: &str,
) -> Result<(), NifError> {
    xml.doc.mutably(env, |txn| {
        xml.reference.insert_attribute(txn, key, value);
        Ok(())
    })
}
#[rustler::nif]
fn xml_element_get_attribute(xml: NifXmlElement, key: &str) -> Option<String> {
    xml.doc
        .readonly(|txn| xml.reference.get_attribute(txn, key))
}

#[rustler::nif]
fn xml_element_remove_attribute(
    env: Env<'_>,
    xml: NifXmlElement,
    key: &str,
) -> Result<(), NifError> {
    xml.doc.mutably(env, |txn| {
        xml.reference.remove_attribute(txn, &key);
        Ok(())
    })
}

#[rustler::nif]
fn xml_element_get_attributes(xml: NifXmlElement) -> HashMap<String, String> {
    xml.doc.readonly(|txn| {
        xml.reference
            .attributes(txn)
            .map(|(key, value)| (key.into(), value))
            .collect()
    })
}

#[rustler::nif]
fn xml_element_next_sibling(xml: NifXmlElement) -> Option<NifYOut> {
    xml.doc.readonly(|txn| {
        xml.reference
            .siblings(txn)
            .next()
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
    })
}

#[rustler::nif]
fn xml_element_prev_sibling(xml: NifXmlElement) -> Option<NifYOut> {
    xml.doc.readonly(|txn| {
        xml.reference
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
    })
}

#[rustler::nif]
fn xml_text_insert(
    env: Env<'_>,
    text: NifXmlText,
    index: u32,
    chunk: &str,
) -> Result<(), NifError> {
    text.doc.mutably(env, |txn| {
        text.reference.insert(txn, index, chunk);
        Ok(())
    })
}

#[rustler::nif]
fn xml_text_insert_with_attributes(
    env: Env<'_>,
    text: NifXmlText,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> Result<(), NifError> {
    text.doc.mutably(env, |txn| {
        text.reference
            .insert_with_attributes(txn, index, chunk, attr.0);
        Ok(())
    })
}

#[rustler::nif]
fn xml_text_delete(env: Env<'_>, text: NifXmlText, index: u32, len: u32) -> Result<(), NifError> {
    text.doc.mutably(env, |txn| {
        text.reference.remove_range(txn, index, len);
        Ok(())
    })
}
#[rustler::nif]
fn xml_text_length(text: NifXmlText) -> u32 {
    text.doc.readonly(|txn| text.reference.len(txn))
}

#[rustler::nif]
fn xml_text_format(
    env: Env<'_>,
    text: NifXmlText,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> Result<(), NifError> {
    text.doc.mutably(env, |txn| {
        text.reference.format(txn, index, len, attr.0);
        Ok(())
    })
}

#[rustler::nif]
fn xml_text_apply_delta(
    env: Env<'_>,
    text: NifXmlText,
    delta: NifYInputDelta,
) -> Result<(), NifError> {
    text.doc.mutably(env, |txn| {
        text.reference.apply_delta(txn, delta.0);
        Ok(())
    })
}

#[rustler::nif]
fn xml_text_next_sibling(xml: NifXmlText) -> Option<NifYOut> {
    xml.doc.readonly(|txn| {
        xml.reference
            .siblings(txn)
            .next()
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
    })
}

#[rustler::nif]
fn xml_text_prev_sibling(xml: NifXmlText) -> Option<NifYOut> {
    xml.doc.readonly(|txn| {
        xml.reference
            .siblings(txn)
            .next_back()
            .map(|b| NifYOut::from_xml_out(b, xml.doc.clone()))
    })
}

#[rustler::nif]
fn xml_text_to_delta(env: Env<'_>, text: NifXmlText) -> NifResult<rustler::Term<'_>> {
    let diff = text
        .doc
        .readonly(|txn| text.reference.diff(txn, YChange::identity));
    encode_diffs(diff, &text.doc, env)
}

#[rustler::nif]
fn xml_text_to_string(xml: NifXmlText) -> String {
    xml.doc.readonly(|txn| xml.reference.get_string(txn).into())
}
