mod any;
mod array;
mod atoms;
mod awareness;
mod doc;
mod error;
mod map;
mod subscription;
mod sync;
mod text;
mod wrap;
mod yinput;
mod youtput;

use any::NifAny;
use array::NifArray;
use doc::{DocResource, NifDoc};
use error::NifError;
use map::NifMap;
use rustler::{Binary, Env, NifStruct, ResourceArc, Term};
use scoped_thread_local::scoped_thread_local;
use text::NifText;
use wrap::encode_binary_slice_to_term;

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
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
fn encode_state_vector_v1(env: Env<'_>, doc: NifDoc) -> Result<Term<'_>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_vector_v1()
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}

#[rustler::nif]
fn encode_state_as_update_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    state_vector: Option<Binary>,
) -> Result<Term<'a>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_as_update_v1(state_vector.map(|b| b.as_slice()))
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}
#[rustler::nif]
fn apply_update_v1(env: Env<'_>, doc: NifDoc, update: Binary) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || doc.apply_update_v1(update.as_slice()))
}

#[rustler::nif]
fn encode_state_vector_v2(env: Env<'_>, doc: NifDoc) -> Result<Term<'_>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_vector_v2()
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}

#[rustler::nif]
fn encode_state_as_update_v2<'a>(
    env: Env<'a>,
    doc: NifDoc,
    state_vector: Option<Binary>,
) -> Result<Term<'a>, NifError> {
    ENV.set(&mut env.clone(), || {
        doc.encode_state_as_update_v2(state_vector.map(|b| b.as_slice()))
            .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
    })
}
#[rustler::nif]
fn apply_update_v2(env: Env<'_>, doc: NifDoc, update: Binary) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || doc.apply_update_v2(update.as_slice()))
}

rustler::init!("Elixir.Yex.Nif");
