use std::collections::HashMap;
use std::sync::Arc;

use crate::wrap::NifWrap;
use rustler::types;
use rustler::{Decoder, Encoder, Env, Error, ListIterator, MapIterator, NifResult, Term};
use yrs::*;

fn encode<'a>(env: Env<'a>, any: &Any) -> Term<'a> {
    match any {
        Any::Null => types::atom::nil().to_term(env),
        Any::Undefined => types::atom::undefined().to_term(env),
        Any::Bool(b) => b.encode(env),
        Any::Number(n) => n.encode(env),
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
    } else if let Ok(v) = term.decode::<i64>() {
        return Ok(Any::BigInt(v));
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

    return Err(rustler::Error::BadArg);
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
