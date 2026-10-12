use std::collections::HashMap;
use std::sync::Arc;

use crate::wrap::{NifStr, NifWrap};
use rustler::dynamic::TermType;
use rustler::types;
use rustler::{
    Binary, Decoder, Encoder, Env, Error, ListIterator, MapIterator, NewBinary, NifResult,
    NifStruct, Term,
};
use yrs::*;

/// `%Yex.Buffer{data: bytes}`: how a buffer reads back, and how bytes are written as one
/// whatever they contain. Strings are binaries too, so a bare binary can only be guessed
/// at (a string when it is valid UTF-8, a buffer otherwise); the struct says which is meant
/// and keeps a value that is read and written again a buffer.
#[derive(NifStruct)]
#[module = "Yex.Buffer"]
struct NifBuffer<'a> {
    data: Binary<'a>,
}

impl<'a> NifBuffer<'a> {
    fn from_slice(env: Env<'a>, bytes: &[u8]) -> Self {
        let mut data = NewBinary::new(env, bytes.len());
        data.as_mut_slice().copy_from_slice(bytes);
        NifBuffer { data: data.into() }
    }
}

fn encode<'a>(env: Env<'a>, any: &Any) -> Term<'a> {
    match any {
        Any::Null => types::atom::nil().to_term(env),
        Any::Undefined => types::atom::undefined().to_term(env),
        Any::Bool(b) => b.encode(env),
        Any::Number(Number::Float(f)) => f.encode(env),
        // Integers within the safe range are exposed as floats, matching how Yjs treats numbers.
        Any::Number(Number::Int(n))
            if (Number::I64_MIN_SAFE_INTEGER..=Number::I64_MAX_SAFE_INTEGER).contains(n) =>
        {
            (*n as f64).encode(env)
        }
        Any::Number(Number::Int(n)) => n.encode(env),
        Any::String(s) => encode_str(env, s),
        Any::Buffer(b) => NifBuffer::from_slice(env, b).encode(env),
        Any::Array(a) => {
            let list: Vec<Term<'a>> = a.iter().map(|item| encode(env, item)).collect();
            list.encode(env)
        }
        Any::Map(m) => encode_map(env, m.iter()),
    }
}

fn encode_str<'a>(env: Env<'a>, s: &str) -> Term<'a> {
    NifStr(s).encode(env)
}

/// Builds the map straight from term arrays; the keys come from a map, so they are unique.
fn encode_map<'a, 'b, K: AsRef<str> + 'b>(
    env: Env<'a>,
    entries: impl ExactSizeIterator<Item = (&'b K, &'b Any)>,
) -> Term<'a> {
    let mut keys = Vec::with_capacity(entries.len());
    let mut values = Vec::with_capacity(entries.len());
    for (k, v) in entries {
        keys.push(encode_str(env, k.as_ref()));
        values.push(encode(env, v));
    }
    Term::map_from_term_arrays(env, &keys, &values).expect("map keys are unique")
}
impl rustler::Encoder for NifAny {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        encode(env, &self.0)
    }
}
fn decode<'a>(term: Term<'a>) -> NifResult<Any> {
    match term.get_type() {
        TermType::Atom => {
            if let Ok(v) = term.decode::<bool>() {
                return Ok(Any::Bool(v));
            }

            let atom = term.decode::<types::atom::Atom>()?;
            if atom == types::atom::nil() {
                return Ok(Any::Null);
            }
            if atom == types::atom::undefined() {
                return Ok(Any::Undefined);
            }

            Err(rustler::Error::BadArg)
        }
        TermType::Integer => term.decode::<i64>().map(|v| Any::Number(Number::Int(v))),
        TermType::Float => term.decode::<f64>().map(|v| Any::Number(Number::Float(v))),
        TermType::Binary => {
            if let Ok(v) = term.decode::<&str>() {
                return Ok(Any::String(v.into()));
            }

            // Binaries that are not valid UTF-8 cannot be strings, so they are taken as a
            // Buffer, which reads back as `%Yex.Buffer{}`.
            term.decode::<Binary>()
                .map(|v| Any::Buffer(v.as_slice().into()))
        }
        TermType::List => {
            let iter = term.decode::<ListIterator<'a>>()?;
            let values = iter
                .map(decode)
                .collect::<Result<Vec<yrs::Any>, rustler::Error>>()?;
            Ok(Any::from(values))
        }
        TermType::Map => {
            if let Ok(buffer) = term.decode::<NifBuffer>() {
                return Ok(Any::Buffer(buffer.data.as_slice().into()));
            }

            let iter = term.decode::<MapIterator<'a>>()?;
            let values = iter
                .map(|(k, v)| Ok((k.decode::<String>()?, decode(v)?)))
                .collect::<Result<HashMap<String, yrs::Any>, rustler::Error>>()?;
            Ok(Any::from(values))
        }
        _ => Err(rustler::Error::BadArg),
    }
}

pub type NifAny = NifWrap<Any>;

impl<'a> Decoder<'a> for NifAny {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        decode(term).map(|any| any.into())
    }
}

pub type NifAttr = NifWrap<HashMap<Arc<str>, Any>>;
impl<'a> Decoder<'a> for NifAttr {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        if let Ok(v) = term.decode::<MapIterator<'a>>() {
            let a = v
                .map(|(k, v)| Ok((k.decode::<&str>()?.into(), decode(v)?)))
                .collect::<Result<HashMap<Arc<str>, yrs::Any>, rustler::Error>>()?;
            return Ok(a.into());
        }
        Err(Error::BadArg)
    }
}

impl rustler::Encoder for NifAttr {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        encode_map(env, self.0.iter())
    }
}

#[rustler::nif]
fn normalize_number(any: NifAny) -> NifAny {
    // The data passes through Any, and gets converted.
    // For example, even numbers within the SAFE_INTEGER range are converted to float type.
    any
}
