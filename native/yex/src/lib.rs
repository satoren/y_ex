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
use rustler::{Env, NifStruct, ResourceArc};
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

rustler::init!("Elixir.Yex.Nif");
