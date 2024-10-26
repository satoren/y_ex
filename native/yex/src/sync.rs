use crate::wrap::SliceIntoBinary;
use crate::{atoms, error::NifError};
use rustler::{Atom, Binary, Encoder as NifEncoder, Env, Term};

use yrs::encoding::read::Cursor;
use yrs::sync::protocol::{
    MSG_AUTH, MSG_AWARENESS, MSG_QUERY_AWARENESS, MSG_SYNC, MSG_SYNC_STEP_1, MSG_SYNC_STEP_2,
    MSG_SYNC_UPDATE, PERMISSION_DENIED, PERMISSION_GRANTED,
};
use yrs::updates::decoder::{Decoder, DecoderV1, DecoderV2};
use yrs::updates::encoder::{Encoder, EncoderV1, EncoderV2};

fn decode_sync_message<'a, D: Decoder>(
    env: Env<'a>,
    decoder: &mut D,
) -> Result<Term<'a>, NifError> {
    let tag: u8 = decoder.read_var()?;
    match tag {
        MSG_SYNC_STEP_1 => {
            let buf = decoder.read_buf()?;
            Ok((atoms::sync_step1(), SliceIntoBinary::new(buf)).encode(env))
        }
        MSG_SYNC_STEP_2 => {
            let buf = decoder.read_buf()?;
            Ok((atoms::sync_step2(), SliceIntoBinary::new(buf)).encode(env))
        }
        MSG_SYNC_UPDATE => {
            let buf = decoder.read_buf()?;
            Ok((atoms::sync_update(), SliceIntoBinary::new(buf)).encode(env))
        }
        _ => Err(NifError::Message(format!("Unexpected tag value: {}", tag))),
    }
}

fn encode_sync_message<'a, E: Encoder>(term: Term<'a>, encoder: &mut E) -> Result<(), NifError> {
    if let Ok((atom, value)) = term.decode::<(Atom, Term<'a>)>() {
        if atom == atoms::sync_step1() {
            encoder.write_var(MSG_SYNC_STEP_1);
            let binary = value.decode::<Binary>()?;
            encoder.write_buf(binary.as_slice());
            return Ok(());
        } else if atom == atoms::sync_step2() {
            encoder.write_var(MSG_SYNC_STEP_2);
            let binary = value.decode::<Binary>()?;
            encoder.write_buf(binary.as_slice());
            return Ok(());
        } else if atom == atoms::sync_update() {
            encoder.write_var(MSG_SYNC_UPDATE);
            let binary = value.decode::<Binary>()?;
            encoder.write_buf(binary.as_slice());
            return Ok(());
        }
    }
    Err(NifError::Message(format!("Unexpected structure")))
}

fn decode_message<'a, D: Decoder>(env: Env<'a>, decoder: &mut D) -> Result<Term<'a>, NifError> {
    let tag: u8 = decoder.read_var()?;
    match tag {
        MSG_SYNC => {
            let sync_message = decode_sync_message(env, decoder)?;
            Ok((atoms::sync(), sync_message).encode(env))
        }
        MSG_AWARENESS => {
            let data = decoder.read_buf()?;
            Ok((atoms::awareness(), SliceIntoBinary::new(data)).encode(env))
        }
        MSG_AUTH => {
            let reason = if decoder.read_var::<u8>()? == PERMISSION_DENIED {
                Some(decoder.read_string()?.to_string())
            } else {
                None
            };
            Ok((atoms::auth(), reason).encode(env))
        }
        MSG_QUERY_AWARENESS => Ok(atoms::query_awareness().encode(env)),
        tag => {
            let data = decoder.read_buf()?;
            Ok((atoms::custom(), tag, SliceIntoBinary::new(data)).encode(env))
        }
    }
}

fn encode_message<'a, E: Encoder>(term: Term<'a>, encoder: &mut E) -> Result<(), NifError> {
    if let Ok((atom, value)) = term.decode::<(Atom, Term<'a>)>() {
        if atom == atoms::sync() {
            encoder.write_var(MSG_SYNC);
            encode_sync_message(value, encoder)?;
            return Ok(());
        } else if atom == atoms::awareness() {
            encoder.write_var(MSG_AWARENESS);
            let binary = value.decode::<Binary>()?;
            encoder.write_buf(binary.as_slice());
            return Ok(());
        } else if atom == atoms::auth() {
            let reason = value.decode::<Option<String>>()?;
            encoder.write_var(MSG_AUTH);

            if let Some(reason) = reason {
                encoder.write_var(PERMISSION_DENIED);
                encoder.write_string(&reason);
            } else {
                encoder.write_var(PERMISSION_GRANTED);
            }
            return Ok(());
        }
    } else if let Ok((atom, tag, value)) = term.decode::<(Atom, u32, Term<'a>)>() {
        if atom == atoms::custom() {
            encoder.write_var(tag);
            let binary = value.decode::<Binary>()?;
            encoder.write_buf(binary.as_slice());
            return Ok(());
        }
    } else if let Ok(atom) = term.decode::<Atom>() {
        if atom == atoms::query_awareness() {
            encoder.write_var(MSG_QUERY_AWARENESS);
            return Ok(());
        }
    }
    return Err(NifError::Message("Unexpected structure".into()));
}

#[rustler::nif]
fn sync_message_decode_v1<'a>(env: Env<'a>, msg: Binary<'a>) -> Result<Term<'a>, NifError> {
    let mut decoder = DecoderV1::new(Cursor::new(msg.as_slice()));
    decode_message(env, &mut decoder)
}

#[rustler::nif]
fn sync_message_encode_v1<'a>(env: Env<'a>, msg: Term<'a>) -> Result<Term<'a>, NifError> {
    let mut encoder = EncoderV1::new();
    encode_message(msg, &mut encoder)?;
    Ok(SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env))
}

#[rustler::nif]
fn sync_message_decode_v2<'a>(env: Env<'a>, msg: Binary<'a>) -> Result<Term<'a>, NifError> {
    let mut decoder = DecoderV2::new(Cursor::new(msg.as_slice()))?;
    decode_message(env, &mut decoder)
}

#[rustler::nif]
fn sync_message_encode_v2<'a>(env: Env<'a>, msg: Term<'a>) -> Result<Term<'a>, NifError> {
    let mut encoder = EncoderV2::new();
    encode_message(msg, &mut encoder)?;
    Ok(SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env))
}
