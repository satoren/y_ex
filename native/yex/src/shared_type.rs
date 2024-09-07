use rustler::{Decoder, Encoder, Env, NifResult, Term};
use serde::{Deserialize, Serialize};
use std::ops::Deref;
use yrs::Hook;

use crate::wrap::encode_binary_slice_to_term;

pub struct NifSharedType<T> {
    hook: Hook<T>,
}
impl<T> NifSharedType<T> {
    pub fn new(v: Hook<T>) -> Self {
        Self { hook: v }
    }
}
impl<T> Deref for NifSharedType<T> {
    type Target = Hook<T>;

    fn deref(&self) -> &Self::Target {
        &self.hook
    }
}
impl<'de, 'a: 'de, T> Encoder for NifSharedType<T> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut s = flexbuffers::FlexbufferSerializer::new();

        self.hook.serialize(&mut s).unwrap();
        encode_binary_slice_to_term(env, s.view())
    }
}
impl<'a, T: 'a> Decoder<'a> for NifSharedType<T> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        let r =
            flexbuffers::Reader::get_root(bin.as_slice()).map_err(|_e| rustler::Error::BadArg)?;
        let hook = Hook::<T>::deserialize(r).map_err(|_e| rustler::Error::BadArg)?;
        Ok(NifSharedType::new(hook))
    }
}
