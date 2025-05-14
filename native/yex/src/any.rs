use std::collections::HashMap;
use std::sync::Arc;

use crate::wrap::NifWrap;
use rustler::types;
use rustler::{Decoder, Encoder, Env, Error, ListIterator, MapIterator, NifResult, Term};
use yrs::any::{F64_MAX_SAFE_INTEGER, F64_MIN_SAFE_INTEGER};
use yrs::*;

fn encode<'a>(env: Env<'a>, any: &Any) -> Term<'a> {
    match any {
        Any::Null => types::atom::nil().to_term(env),
        Any::Undefined => types::atom::undefined().to_term(env),
        Any::Bool(b) => b.encode(env),
        Any::Number(num) => num.encode(env),
        Any::BigInt(n) => n.encode(env),
        Any::String(s) => s.encode(env),
        Any::Buffer(b) => b.encode(env),
        Any::Array(a) => {
            let list: Vec<Term<'a>> = a.iter().map(|item| encode(env, item)).collect();
            list.encode(env)
        }
        Any::Map(m) => {
            let map: HashMap<String, NifAny> = m
                .iter()
                .map(|(k, v)| (k.into(), v.clone().into()))
                .collect();
            map.encode(env)
        }
    }
}
impl<'de, 'a: 'de> rustler::Encoder for NifAny {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        encode(env, &self.0)
    }
}
fn decode<'a>(term: Term<'a>) -> NifResult<Any> {
    if let Ok(v) = term.decode::<bool>() {
        return Ok(Any::Bool(v));
    } else if let Ok(atom) = term.decode::<types::atom::Atom>() {
        if atom == types::atom::nil() {
            return Ok(Any::Null);
        } else if atom == types::atom::undefined() {
            return Ok(Any::Undefined);
        }
        return Err(rustler::Error::BadArg);
    } else if let Ok(v) = term.decode::<i32>() {
        return Ok(Any::Number(v.into()));
    } else if let Ok(v) = term.decode::<i64>() {
        // Check if the number is within the safe integer range for f64
        // If it is not, we return it as a BigInt
        if v > F64_MAX_SAFE_INTEGER as i64 || v < F64_MIN_SAFE_INTEGER as i64 {
            return Ok(Any::BigInt(v.into()));
        }
        return Ok(Any::Number(v as f64));
    } else if let Ok(v) = term.decode::<f64>() {
        return Ok(Any::Number(v));
    } else if let Ok(v) = term.decode::<&str>() {
        return Ok(Any::String(v.into()));
    } else if let Ok(v) = term.decode::<Vec<u8>>() {
        return Ok(Any::Buffer(v.into()));
    } else if let Ok(v) = term.decode::<ListIterator<'a>>() {
        let a = v
            .map(|v| decode(v))
            .collect::<Result<Vec<yrs::Any>, rustler::Error>>()?;
        return Ok(Any::from(a));
    } else if let Ok(v) = term.decode::<MapIterator<'a>>() {
        let a = v
            .map(|(k, v)| Ok((k.decode::<String>()?, decode(v)?)))
            .collect::<Result<HashMap<String, yrs::Any>, rustler::Error>>()?;
        return Ok(Any::from(a));
    }

    Err(rustler::Error::BadArg)
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

impl<'de, 'a: 'de> rustler::Encoder for NifAttr {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let map: HashMap<String, NifAny> = self
            .0
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone().into()))
            .collect();
        map.encode(env)
    }
}

#[rustler::nif]
fn normalize_number(any: NifAny) -> NifAny {
    any
}
