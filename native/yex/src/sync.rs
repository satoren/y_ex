use crate::atoms;
use crate::awareness::NifAwareness;
use crate::doc::NifDoc;
use crate::error::Error;
use crate::transaction::TransactionResource;
use crate::wrap::SliceIntoBinary;
use rustler::{Atom, Binary, Encoder as NifEncoder, Env, NifResult, ResourceArc, Term};

use yrs::encoding::read::{Cursor, Read};
use yrs::encoding::write::Write;
use yrs::sync::protocol::{
    MSG_AUTH, MSG_AWARENESS, MSG_QUERY_AWARENESS, MSG_SYNC, MSG_SYNC_STEP_1, MSG_SYNC_STEP_2,
    MSG_SYNC_UPDATE, PERMISSION_DENIED, PERMISSION_GRANTED,
};
use yrs::updates::decoder::{Decode, Decoder, DecoderV1, DecoderV2};
use yrs::updates::encoder::{Encode, Encoder, EncoderV1, EncoderV2};
use yrs::{ReadTxn, StateVector};

fn decode_sync_message<'a, D: Decoder>(env: Env<'a>, decoder: &mut D) -> Result<Term<'a>, Error> {
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
        _ => Err(Error::Message(format!("Unexpected tag value: {}", tag))),
    }
}

fn encode_sync_message<'a, E: Encoder>(term: Term<'a>, encoder: &mut E) -> Result<(), Error> {
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
    Err(Error::Message("Unexpected structure".to_string()))
}

fn decode_message<'a, D: Decoder>(env: Env<'a>, decoder: &mut D) -> Result<Term<'a>, Error> {
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

fn encode_message<'a, E: Encoder>(term: Term<'a>, encoder: &mut E) -> Result<(), Error> {
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
    Err(Error::Message("Unexpected structure".into()))
}

fn encode_sync_step2_term<'a>(env: Env<'a>, payload: &[u8]) -> Term<'a> {
    let mut encoder = EncoderV1::new();
    encoder.write_var(MSG_SYNC);
    encoder.write_var(MSG_SYNC_STEP_2);
    encoder.write_buf(payload);
    SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env)
}

fn encode_sync_step1_term<'a>(env: Env<'a>, payload: &[u8]) -> Term<'a> {
    let mut encoder = EncoderV1::new();
    encoder.write_var(MSG_SYNC);
    encoder.write_var(MSG_SYNC_STEP_1);
    encoder.write_buf(payload);
    SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env)
}

fn encode_awareness_term<'a>(env: Env<'a>, payload: &[u8]) -> Term<'a> {
    let mut encoder = EncoderV1::new();
    encoder.write_var(MSG_AWARENESS);
    encoder.write_buf(payload);
    SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env)
}

#[rustler::nif]
fn sync_message_decode_v1<'a>(env: Env<'a>, msg: Binary<'a>) -> NifResult<(Atom, Term<'a>)> {
    let mut decoder = DecoderV1::new(Cursor::new(msg.as_slice()));
    decode_message(env, &mut decoder)
        .map(|term| (atoms::ok(), term))
        .map_err(|e| e.into())
}

#[rustler::nif]
fn sync_message_encode_v1<'a>(env: Env<'a>, msg: Term<'a>) -> NifResult<(Atom, Term<'a>)> {
    let mut encoder = EncoderV1::new();
    encode_message(msg, &mut encoder)?;
    Ok((
        atoms::ok(),
        SliceIntoBinary::new(encoder.to_vec().as_slice()).encode(env),
    ))
}

/// Encode several v1 protocol messages in one NIF call (fewer BEAM↔native transitions).
#[rustler::nif]
fn sync_messages_encode_v1<'a>(env: Env<'a>, msgs: Term<'a>) -> NifResult<Term<'a>> {
    let msgs_vec: Vec<Term<'a>> = msgs.decode()?;
    let mut bins = Vec::with_capacity(msgs_vec.len());
    for msg in msgs_vec {
        let mut encoder = EncoderV1::new();
        encode_message(msg, &mut encoder)?;
        let encoded = encoder.to_vec();
        bins.push(SliceIntoBinary::new(encoded.as_slice()).encode(env));
    }
    Ok((atoms::ok(), bins).encode(env))
}

#[rustler::nif]
fn sync_step1_replies_encode_v1<'a>(
    env: Env<'a>,
    diff: Binary<'a>,
    state_vector: Binary<'a>,
    awareness_update: Option<Binary<'a>>,
) -> NifResult<Term<'a>> {
    let mut bins = Vec::with_capacity(if awareness_update.is_some() { 3 } else { 2 });

    bins.push(encode_sync_step2_term(env, diff.as_slice()));
    bins.push(encode_sync_step1_term(env, state_vector.as_slice()));

    if let Some(awareness_update) = awareness_update {
        bins.push(encode_awareness_term(env, awareness_update.as_slice()));
    }

    Ok((atoms::ok(), bins).encode(env))
}

#[rustler::nif]
fn encode_awareness_reply_v1<'a>(env: Env<'a>, awareness: NifAwareness) -> NifResult<Term<'a>> {
    let update = awareness.reference.update().map_err(Error::from)?;
    let update_bytes = update.encode_v1();
    Ok((
        atoms::ok(),
        vec![encode_awareness_term(env, update_bytes.as_slice())],
    )
        .encode(env))
}

/// Decode sync_step1 sv_payload, compute diff+sv, encode awareness, return all message binaries.
/// sv_payload is the raw bytes after MSG_SYNC + MSG_SYNC_STEP_1 (i.e. varint_len + sv_bytes).
#[rustler::nif]
fn encode_sync_step1_response_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    sv_payload: Binary<'a>,
    awareness: Option<NifAwareness>,
) -> NifResult<Term<'a>> {
    let mut decoder = DecoderV1::new(Cursor::new(sv_payload.as_slice()));
    let sv_bytes = decoder.read_buf().map_err(Error::from)?;
    let sv = StateVector::decode_v1(sv_bytes).map_err(Error::from)?;

    let (diff, local_sv) = doc.readonly(current_transaction, |txn| {
        let diff = txn.encode_diff_v1(&sv);
        let local_sv = txn.state_vector().encode_v1();
        Ok((diff, local_sv))
    })?;

    let awareness_bytes = if let Some(aw) = awareness {
        Some(aw.reference.update().map_err(Error::from)?.encode_v1())
    } else {
        None
    };

    let mut bins = Vec::with_capacity(if awareness_bytes.is_some() { 3 } else { 2 });

    bins.push(encode_sync_step2_term(env, diff.as_slice()));
    bins.push(encode_sync_step1_term(env, local_sv.as_slice()));

    if let Some(au) = awareness_bytes {
        bins.push(encode_awareness_term(env, au.as_slice()));
    }

    Ok((atoms::ok(), bins).encode(env))
}

#[rustler::nif]
fn awareness_message_encode_v1<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    Ok((atoms::ok(), encode_awareness_term(env, update.as_slice())).encode(env))
}

#[rustler::nif]
fn sync_message_decode_v2<'a>(env: Env<'a>, msg: Binary<'a>) -> NifResult<(Atom, Term<'a>)> {
    let mut decoder = DecoderV2::new(Cursor::new(msg.as_slice())).map_err(Error::from)?;
    decode_message(env, &mut decoder)
        .map(|term| (atoms::ok(), term))
        .map_err(|e| e.into())
}

#[rustler::nif]
fn sync_message_encode_v2<'a>(env: Env<'a>, msg: Term<'a>) -> NifResult<Term<'a>> {
    let mut encoder = EncoderV2::new();
    encode_message(msg, &mut encoder)?;
    Ok((
        atoms::ok(),
        SliceIntoBinary::new(encoder.to_vec().as_slice()),
    )
        .encode(env))
}
