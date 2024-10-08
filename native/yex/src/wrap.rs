use std::ops::Deref;

use rustler::{Env, Term};

pub struct NifWrap<T>(pub T);

impl<T> From<T> for NifWrap<T> {
    fn from(w: T) -> NifWrap<T> {
        NifWrap::<T>(w)
    }
}

impl<T> Deref for NifWrap<T> {
    type Target = T;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

pub fn encode_binary_slice_to_term<'a>(env: Env<'a>, vec: &[u8]) -> Term<'a> {
    let mut bin = rustler::NewBinary::new(env, vec.len());
    bin.as_mut_slice().copy_from_slice(vec);
    bin.into()
}
