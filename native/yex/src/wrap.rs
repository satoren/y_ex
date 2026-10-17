use std::ops::Deref;

use rustler::sys::{enif_make_map_from_arrays, ERL_NIF_TERM};
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
        make_map(
            env,
            self.0
                .iter()
                .map(|(k, v)| (NifStr(k).encode(env), v.encode(env))),
        )
    }
}

/// Maps up to this size are built from arrays on the stack. Erlang keeps maps this small
/// flat, so this covers most maps a document holds.
const STACK_MAP_ENTRIES: usize = 32;

/// Builds a map from entries with unique keys. Unlike `Term::map_from_term_arrays`, small
/// maps need no heap allocation for their key and value arrays.
pub fn make_map<'a>(
    env: Env<'a>,
    entries: impl IntoIterator<Item = (Term<'a>, Term<'a>)>,
) -> Term<'a> {
    let entries = entries.into_iter();
    let fits_stack = entries
        .size_hint()
        .1
        .is_some_and(|max| max <= STACK_MAP_ENTRIES);
    let map = if fits_stack {
        let mut keys = [0 as ERL_NIF_TERM; STACK_MAP_ENTRIES];
        let mut values = [0 as ERL_NIF_TERM; STACK_MAP_ENTRIES];
        let mut len = 0;
        for (k, v) in entries.take(STACK_MAP_ENTRIES) {
            keys[len] = k.as_c_arg();
            values[len] = v.as_c_arg();
            len += 1;
        }
        map_from_arrays(env, &keys[..len], &values[..len])
    } else {
        let (keys, values): (Vec<ERL_NIF_TERM>, Vec<ERL_NIF_TERM>) =
            entries.map(|(k, v)| (k.as_c_arg(), v.as_c_arg())).unzip();
        map_from_arrays(env, &keys, &values)
    };
    map.expect("map keys are unique")
}

fn map_from_arrays<'a>(
    env: Env<'a>,
    keys: &[ERL_NIF_TERM],
    values: &[ERL_NIF_TERM],
) -> Option<Term<'a>> {
    debug_assert_eq!(keys.len(), values.len());
    let mut map: ERL_NIF_TERM = 0;
    // SAFETY: both arrays hold `keys.len()` terms of `env`, and `map` is written on success.
    let ok = unsafe {
        enif_make_map_from_arrays(
            env.as_c_arg(),
            keys.as_ptr(),
            values.as_ptr(),
            keys.len(),
            &mut map,
        )
    };
    (ok != 0).then(|| unsafe { Term::new(env, map) })
}

/// Builds a list by prepending from the back, so no intermediate array is allocated.
/// `items` is consumed back to front.
pub fn make_list<'a>(env: Env<'a>, items: impl DoubleEndedIterator<Item = Term<'a>>) -> Term<'a> {
    items.rev().fold(Term::list_new_empty(env), |list, item| {
        list.list_prepend(item)
    })
}
