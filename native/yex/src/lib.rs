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
mod transaction;
mod undo;
mod utils;
mod weak;
mod wrap;
mod xml;
mod yinput;
mod youtput;

use any::NifAny;
use array::NifArray;
use doc::NifDoc;
use error::Error;
use map::NifMap;
use rustler::{Env, NifStruct};
use scoped_thread_local::scoped_thread_local;
use text::NifText;
use weak::NifWeakLink;

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
}

#[derive(NifStruct)]
#[module = "Yex.UndefinedRef"]
pub struct NifUndefinedRef {
    // not supported yet or...?
    doc: NifDoc,
}

rustler::init!("Elixir.Yex.Nif");
