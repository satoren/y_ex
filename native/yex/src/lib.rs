mod any;
mod array;
mod atoms;
mod doc;
mod error;
mod map;
mod subscription;
mod text;
mod wrap;
mod yinput;
mod youtput;

use std::collections::HashMap;

use any::{NifAny, NifAttr};
use array::NifArray;
use doc::{DocResource, NifDoc, NifOptions};
use error::NifError;
use map::NifMap;
use rustler::{Binary, Env, LocalPid, NifStruct, NifUnitEnum, ResourceArc, Term};
use scoped_thread_local::scoped_thread_local;
use subscription::SubscriptionResource;
use text::NifText;
use wrap::encode_binary_slice_to_term;
use yinput::NifYInput;
use youtput::NifValue;

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
}

#[derive(NifUnitEnum)]
pub enum NifOffsetKind {
    Bytes,
    Utf16,
}

#[derive(NifStruct)]
#[module = "Yex.XmlFragment"]
struct NifXmlFragment {}
#[derive(NifStruct)]
#[module = "Yex.XmlElement"]
pub struct NifXmlElement {
    // not supported yet
    doc: ResourceArc<DocResource>,
}

#[derive(NifStruct)]
#[module = "Yex.XmlText"]
pub struct NifXmlText {
    // not supported yet
    doc: ResourceArc<DocResource>,
}

#[derive(NifStruct)]
#[module = "Yex.WeakLink"]
pub struct NifWeakLink {
    // not supported yet
    doc: ResourceArc<DocResource>,
}

#[derive(NifStruct)]
#[module = "Yex.UndefinedRef"]
pub struct NifUndefinedRef {
    // not supported yet or...?
    doc: ResourceArc<DocResource>,
}

#[rustler::nif]
fn doc_new() -> NifDoc {
    NifDoc::default()
}

#[rustler::nif]
fn doc_with_options(option: NifOptions) -> NifDoc {
    NifDoc::with_options(option)
}

#[rustler::nif]
fn doc_get_or_insert_text(env: Env<'_>, doc: NifDoc, name: &str) -> NifText {
    ENV.set(&mut env.clone(), || doc.get_or_insert_text(name))
}

#[rustler::nif]
fn doc_get_or_insert_array(env: Env<'_>, doc: NifDoc, name: &str) -> NifArray {
    ENV.set(&mut env.clone(), || doc.get_or_insert_array(name))
}

#[rustler::nif]
fn doc_get_or_insert_map(env: Env<'_>, doc: NifDoc, name: &str) -> NifMap {
    ENV.set(&mut env.clone(), || doc.get_or_insert_map(name))
}

#[rustler::nif]
fn doc_begin_transaction(doc: NifDoc, origin: Option<&str>) -> Result<(), NifError> {
    if let Some(origin) = origin {
        doc.begin_transaction_with(origin)
    } else {
        doc.begin_transaction()
    }
}

#[rustler::nif]
fn doc_commit_transaction(env: Env<'_>, doc: NifDoc) {
    ENV.set(&mut env.clone(), || doc.commit_transaction())
}

#[rustler::nif]
fn doc_monitor_update_v1(
    doc: NifDoc,
    pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    doc.monitor_update_v1(pid)
}
#[rustler::nif]
fn doc_monitor_update_v2(
    doc: NifDoc,
    pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    doc.monitor_update_v2(pid)
}

#[rustler::nif]
fn text_insert(env: Env<'_>, text: NifText, index: u32, chunk: &str) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.insert(index, chunk))
}

#[rustler::nif]
fn text_insert_with_attributes(
    env: Env<'_>,
    text: NifText,
    index: u32,
    chunk: &str,
    attr: NifAttr,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        text.insert_with_attributes(index, chunk, attr)
    })
}

#[rustler::nif]
fn text_delete(env: Env<'_>, text: NifText, index: u32, len: u32) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.delete(index, len))
}

#[rustler::nif]
fn text_format(
    env: Env<'_>,
    text: NifText,
    index: u32,
    len: u32,
    attr: NifAttr,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || text.format(index, len, attr))
}

#[rustler::nif]
fn text_to_string(text: NifText) -> String {
    text.to_string()
}
#[rustler::nif]
fn text_length(text: NifText) -> u32 {
    text.length()
}

#[rustler::nif]
fn array_insert(
    env: Env<'_>,
    array: NifArray,
    index: u32,
    value: NifYInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || array.insert(index, value))
}
#[rustler::nif]
fn array_length(array: NifArray) -> u32 {
    array.length()
}
#[rustler::nif]
fn array_get(array: NifArray, index: u32) -> Result<NifValue, NifError> {
    array.get(index)
}
#[rustler::nif]
fn array_delete_range(
    env: Env<'_>,
    array: NifArray,
    index: u32,
    length: u32,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || array.delete_range(index, length))
}
#[rustler::nif]
fn array_to_list(array: NifArray) -> Vec<NifValue> {
    array.to_list()
}
#[rustler::nif]
fn array_to_json(array: NifArray) -> NifAny {
    array.to_json()
}

#[rustler::nif]
fn map_set(env: Env<'_>, map: NifMap, key: &str, value: NifYInput) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || map.set(key, value))
}
#[rustler::nif]
fn map_size(map: NifMap) -> u32 {
    map.size()
}
#[rustler::nif]
fn map_get(map: NifMap, key: &str) -> Result<NifValue, NifError> {
    map.get(key)
}
#[rustler::nif]
fn map_delete(env: Env<'_>, map: NifMap, key: &str) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || map.delete(key))
}
#[rustler::nif]
fn map_to_map(map: NifMap) -> HashMap<String, NifValue> {
    map.to_map()
}
#[rustler::nif]
fn map_to_json(map: NifMap) -> NifAny {
    map.to_json()
}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: ResourceArc<SubscriptionResource>) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        *sub.borrow_mut() = None;
        Ok(())
    })
}

#[rustler::nif]
fn encode_state_vector(env: Env<'_>, doc: NifDoc) -> Result<Term<'_>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_vector()
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}

#[rustler::nif]
fn encode_state_as_update<'a>(
    env: Env<'a>,
    doc: NifDoc,
    state_vector: Option<Binary>,
) -> Result<Term<'a>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_as_update(state_vector.map(|b| b.as_slice()))
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}
#[rustler::nif]
fn apply_update(env: Env<'_>, doc: NifDoc, update: Binary) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || doc.apply_update(update.as_slice()))
}

rustler::init!("Elixir.Yex.Nif");
