mod any;
mod array;
mod atoms;
mod awareness;
mod doc;
mod error;
mod event;
mod map;
mod shared_type;
mod sticky_index;
mod subscription;
mod sync;
mod term_box;
mod text;
mod undo;
mod utils;
mod wrap;
mod xml;
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

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
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
