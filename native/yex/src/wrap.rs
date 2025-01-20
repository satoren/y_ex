use std::ops::Deref;

use rustler::{Env, Term};

pub struct NifWrap<T>(pub T);

impl<T> From<T> for NifWrap<T> {
    fn from(w: T) -> NifWrap<T> {
        NifWrap::<T>(w)
    }
}

impl<T> std::panic::RefUnwindSafe for NifWrap<T> {}

impl<T> Deref for NifWrap<T> {
    type Target = T;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

pub struct SliceIntoBinary<'a> {
    bytes: &'a [u8],
}
impl<'a> SliceIntoBinary<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        SliceIntoBinary { bytes }
    }
}

impl<'a> rustler::Encoder for SliceIntoBinary<'a> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut bin = rustler::NewBinary::new(env, self.bytes.len());
        bin.as_mut_slice().copy_from_slice(self.bytes);
        bin.into()
    }
}
