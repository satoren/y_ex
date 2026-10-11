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

impl rustler::Encoder for SliceIntoBinary<'_> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut bin = rustler::NewBinary::new(env, self.bytes.len());
        bin.as_mut_slice().copy_from_slice(self.bytes);
        bin.into()
    }
}

/// A string that encodes as an on-heap binary when small. Rustler's own `String`
/// encoder always allocates a reference-counted off-heap binary, which costs far more
/// for the short keys and values documents are made of.
pub struct NifStr<T>(pub T);

impl<T: AsRef<str>> rustler::Encoder for NifStr<T> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        SliceIntoBinary::new(self.0.as_ref().as_bytes()).encode(env)
    }
}

/// Key/value pairs with unique keys that encode as a map, built in one call instead of
/// going through a `HashMap`.
pub struct NifMapPairs<V>(pub Vec<(String, V)>);

impl<V> FromIterator<(String, V)> for NifMapPairs<V> {
    fn from_iter<I: IntoIterator<Item = (String, V)>>(iter: I) -> Self {
        NifMapPairs(iter.into_iter().collect())
    }
}

impl<V: rustler::Encoder> rustler::Encoder for NifMapPairs<V> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let (keys, values): (Vec<Term<'b>>, Vec<Term<'b>>) = self
            .0
            .iter()
            .map(|(k, v)| (NifStr(k).encode(env), v.encode(env)))
            .unzip();
        Term::map_from_term_arrays(env, &keys, &values).expect("map keys are unique")
    }
}
