use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

use yrs::encoding::read::{Cursor, Error as ReadError, Read};
use yrs::updates::decoder::{Decode, Decoder, DecoderV1, DecoderV2};
use yrs::{Any, Update, ID};

use crate::error::Error;
use crate::utils::MAX_CLIENT_ID;

/// Runs a lib0 v2 decode and turns a panic inside yrs into an encoding error.
///
/// yrs 0.28 `DecoderV2::read_usize` (updates/decoder.rs) checks the input length once
/// before its varint loop, so a column length whose continuation bits run to the end of
/// the input (for example `<<0, 128>>`) indexes past the buffer and panics. Every v2
/// decode goes through `DecoderV2::new`, which reads those lengths first. This keeps
/// malformed remote input on the `{:error, {:encoding_exception, msg}}` path that v1
/// decode errors already take, until yrs moves the check inside the loop.
pub fn catch_decode_v2<T>(decode: impl FnOnce() -> Result<T, ReadError>) -> Result<T, Error> {
    catch_unwind(AssertUnwindSafe(decode))
        .unwrap_or_else(|_| Err(ReadError::Custom("malformed v2 encoding".to_string())))
        .map_err(Error::from)
}

/// Decodes a v1 value, rejecting client ids above `MAX_CLIENT_ID` (see [ClientIdCheck]).
pub fn decode_v1<T: Decode>(bytes: &[u8]) -> Result<T, Error> {
    Ok(ClientIdCheck::v1(bytes).decode()?)
}

/// Decodes a v2 update, rejecting client ids above `MAX_CLIENT_ID` (see [ClientIdCheck]).
pub fn decode_update_v2(bytes: &[u8]) -> Result<Update, Error> {
    catch_decode_v2(|| ClientIdCheck::v2(bytes)?.decode())
}

fn invalid_client_id(client: u64) -> ReadError {
    ReadError::Custom(format!(
        "client id {client} is out of range 0..{MAX_CLIENT_ID}"
    ))
}

/// Rejects an awareness update holding a client id above `MAX_CLIENT_ID`.
///
/// `AwarenessUpdate::decode` builds each `ClientID` straight from the wire, which in a
/// release build keeps only the low 53 bits, so `2^53 + n` would overwrite client `n`.
/// Malformed input is left for `AwarenessUpdate::decode` to report.
pub fn check_awareness_client_ids(bytes: &[u8]) -> Result<(), Error> {
    let mut cursor = Cursor::new(bytes);
    let Ok(len) = cursor.read_var::<u64>() else {
        return Ok(());
    };
    for _ in 0..len {
        let Ok(client) = cursor.read_var::<u64>() else {
            break;
        };
        if client > MAX_CLIENT_ID {
            return Err(invalid_client_id(client).into());
        }
        if cursor.read_var::<u32>().is_err() || cursor.read_buf().is_err() {
            break;
        }
    }
    Ok(())
}

/// A lib0 decoder wrapper that rejects client ids above `MAX_CLIENT_ID`.
///
/// yrs 0.28 `ClientID::new` only debug-asserts the 53-bit range and masks off higher bits
/// in a release build, and the yrs decoders call it on the raw wire value. A peer could
/// then send blocks as client `2^53 + n` that are integrated as client `n`. The masked
/// `ClientID` can't be told apart afterwards, so this wrapper reads each raw client id
/// just before the inner decoder consumes it:
///
/// - v1 keeps every client id in the main buffer, so it is peeked from there.
/// - v2 keeps block client ids in their own RLE column, which is read in step with the
///   inner decoder, and delete set client ids in the main buffer.
///
/// Delete set client ids are read with a plain `read_var` right after `reset_ds_cur_val`,
/// which can't return an error. An out-of-range one is recorded there, and every read
/// after it fails, so the id never reaches `ClientID::new`; [ClientIdCheck::decode] then
/// reports it.
pub struct ClientIdCheck<'a, D> {
    inner: D,
    clients: Option<ClientColumn<'a>>,
    invalid: Option<u64>,
}

impl<'a> ClientIdCheck<'a, DecoderV1<'a>> {
    pub fn v1(bytes: &'a [u8]) -> Self {
        ClientIdCheck {
            inner: DecoderV1::from(bytes),
            clients: None,
            invalid: None,
        }
    }
}

impl<'a> ClientIdCheck<'a, DecoderV2<'a>> {
    /// Can panic on malformed input inside yrs `DecoderV2::new`; call it within
    /// [catch_decode_v2].
    pub fn v2(bytes: &'a [u8]) -> Result<Self, ReadError> {
        let inner = DecoderV2::new(Cursor::new(bytes))?;
        Ok(ClientIdCheck {
            inner,
            clients: Some(ClientColumn::new(bytes)?),
            invalid: None,
        })
    }
}

impl<'a, D: Decoder> ClientIdCheck<'a, D> {
    pub fn decode<T: Decode>(&mut self) -> Result<T, ReadError> {
        let result = T::decode(self);
        match self.invalid {
            Some(client) => Err(invalid_client_id(client)),
            None => result,
        }
    }

    fn check_recorded(&self) -> Result<(), ReadError> {
        self.invalid
            .map_or(Ok(()), |client| Err(invalid_client_id(client)))
    }

    /// The varint at the read position of the main buffer, without consuming it.
    fn peek_var(&mut self) -> Option<u64> {
        let rest = self.inner.read_to_end().ok()?;
        Cursor::new(rest).read_var().ok()
    }

    /// Checks the client id the inner decoder reads next for a block or block origin.
    /// A read failure is left for the inner decoder to report.
    fn check_next_client(&mut self) -> Result<(), ReadError> {
        let client = match &mut self.clients {
            Some(column) => column.read().ok(),
            None => self.peek_var(),
        };
        match client {
            Some(client) if client > MAX_CLIENT_ID => Err(invalid_client_id(client)),
            _ => Ok(()),
        }
    }
}

impl<'a, D: Decoder> Read for ClientIdCheck<'a, D> {
    fn read_exact(&mut self, len: usize) -> Result<&[u8], ReadError> {
        self.check_recorded()?;
        self.inner.read_exact(len)
    }

    fn read_u8(&mut self) -> Result<u8, ReadError> {
        self.check_recorded()?;
        self.inner.read_u8()
    }

    fn read_string(&mut self) -> Result<&str, ReadError> {
        self.inner.read_string()
    }
}

impl<'a, D: Decoder> Decoder for ClientIdCheck<'a, D> {
    fn reset_ds_cur_val(&mut self) {
        self.inner.reset_ds_cur_val();
        // Called right before the delete set reads a client id from the main buffer.
        if self.invalid.is_none() {
            self.invalid = self.peek_var().filter(|&client| client > MAX_CLIENT_ID);
        }
    }

    fn read_ds_clock(&mut self) -> Result<u32, ReadError> {
        self.inner.read_ds_clock()
    }

    fn read_ds_len(&mut self) -> Result<u32, ReadError> {
        self.inner.read_ds_len()
    }

    fn read_left_id(&mut self) -> Result<ID, ReadError> {
        self.check_next_client()?;
        self.inner.read_left_id()
    }

    fn read_right_id(&mut self) -> Result<ID, ReadError> {
        self.check_next_client()?;
        self.inner.read_right_id()
    }

    fn read_client(&mut self) -> Result<yrs::ClientID, ReadError> {
        self.check_next_client()?;
        self.inner.read_client()
    }

    fn read_info(&mut self) -> Result<u8, ReadError> {
        self.inner.read_info()
    }

    fn read_parent_info(&mut self) -> Result<bool, ReadError> {
        self.inner.read_parent_info()
    }

    fn read_type_ref(&mut self) -> Result<u8, ReadError> {
        self.inner.read_type_ref()
    }

    fn read_len(&mut self) -> Result<u32, ReadError> {
        self.inner.read_len()
    }

    fn read_any(&mut self) -> Result<Any, ReadError> {
        self.inner.read_any()
    }

    fn read_json(&mut self) -> Result<Any, ReadError> {
        self.inner.read_json()
    }

    fn read_key(&mut self) -> Result<Arc<str>, ReadError> {
        self.inner.read_key()
    }

    fn read_to_end(&mut self) -> Result<&[u8], ReadError> {
        self.inner.read_to_end()
    }
}

/// The client id column of a v2 update: an unsigned optional-RLE column, decoded as in
/// yrs `UIntOptRleDecoder`.
struct ClientColumn<'a> {
    cursor: Cursor<'a>,
    last: u64,
    count: u32,
}

impl<'a> ClientColumn<'a> {
    /// Locates the column in the v2 header: an optional feature byte, then length-prefixed
    /// columns starting with key clocks and clients.
    fn new(bytes: &'a [u8]) -> Result<Self, ReadError> {
        let mut header = Cursor::new(bytes);
        if header.has_content() {
            header.read_u8()?;
        }
        let mut read_column = || -> Result<&'a [u8], ReadError> {
            let len =
                usize::try_from(header.read_var::<u64>()?).map_err(|_| ReadError::InvalidVarInt)?;
            let start = header.next;
            let end = start.checked_add(len).filter(|&end| end <= bytes.len());
            let end = end.ok_or(ReadError::EndOfBuffer(len))?;
            header.next = end;
            Ok(&bytes[start..end])
        };
        let _key_clocks = read_column()?;
        let column = read_column()?;
        Ok(ClientColumn {
            cursor: Cursor::new(column),
            last: 0,
            count: 0,
        })
    }

    fn read(&mut self) -> Result<u64, ReadError> {
        if self.count == 0 {
            let s = self.cursor.read_var_signed::<i64>()?;
            if s.is_negative() {
                self.count = self.cursor.read_var::<u32>()?.saturating_add(2);
                self.last = s.value().unsigned_abs();
            } else {
                self.count = 1;
                self.last = s.value() as u64;
            }
        }
        self.count -= 1;
        Ok(self.last)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncated_column_length_is_an_encoding_error() {
        for bytes in [&[0, 128][..], &[255, 255, 255][..]] {
            assert!(matches!(decode_update_v2(bytes), Err(Error::Encoding(_))));
        }
    }

    #[test]
    fn valid_input_and_ordinary_errors_pass_through() {
        use yrs::updates::encoder::Encode;
        assert!(decode_update_v2(&Update::new().encode_v2()).is_ok());
        assert!(matches!(decode_update_v2(&[]), Err(Error::Encoding(_))));
    }

    const OVER: u64 = MAX_CLIENT_ID + 1;

    fn var(mut n: u64, out: &mut Vec<u8>) {
        while n >= 0x80 {
            out.push((n as u8 & 0x7f) | 0x80);
            n >>= 7;
        }
        out.push(n as u8);
    }

    fn signed_var(n: u64, out: &mut Vec<u8>) {
        let more = n >= 0x40;
        out.push((n as u8 & 0x3f) | if more { 0x80 } else { 0 });
        if more {
            var(n >> 6, out);
        }
    }

    /// `head`, the varint `client`, then `tail`.
    fn with_client(head: &[u8], client: u64, tail: &[u8]) -> Vec<u8> {
        let mut out = head.to_vec();
        var(client, &mut out);
        out.extend(tail);
        out
    }

    fn is_out_of_range<T>(result: Result<T, Error>) -> bool {
        matches!(result, Err(Error::Encoding(ReadError::Custom(msg))) if msg.contains("out of range"))
    }

    /// v1 update with one GC block written by `client`.
    fn v1_block(client: u64) -> Vec<u8> {
        with_client(&[1, 1], client, &[0, 0, 1, 0])
    }

    /// v1 update with one deleted item of client 5 whose left origin is `client`.
    fn v1_origin(client: u64) -> Vec<u8> {
        with_client(&[1, 1, 5, 0, 0x81], client, &[0, 1, 0])
    }

    /// v1 update with no blocks and a delete set entry for `client`.
    fn v1_delete_set(client: u64) -> Vec<u8> {
        with_client(&[0, 1], client, &[1, 0, 1])
    }

    /// v2 update: header columns, with `client` alone in the client column, then `rest`.
    fn v2(client: u64, rest: &[u8]) -> Vec<u8> {
        let mut column = Vec::new();
        signed_var(client, &mut column);
        let mut out = vec![0, 0, column.len() as u8];
        out.extend(column);
        // left/right clocks, info (GC), string, parent info, type ref, len (1)
        out.extend([0, 0, 1, 0, 1, 0, 0, 0, 1, 1]);
        out.extend(rest);
        out
    }

    #[test]
    fn v1_client_ids_in_range_decode() {
        for client in [5, MAX_CLIENT_ID] {
            assert!(decode_v1::<Update>(&v1_block(client)).is_ok());
            assert!(decode_v1::<Update>(&v1_origin(client)).is_ok());
            assert!(decode_v1::<Update>(&v1_delete_set(client)).is_ok());
        }
    }

    #[test]
    fn v1_client_ids_out_of_range_are_rejected() {
        for client in [OVER, OVER + 5, u64::MAX] {
            assert!(is_out_of_range(decode_v1::<Update>(&v1_block(client))));
            assert!(is_out_of_range(decode_v1::<Update>(&v1_origin(client))));
            assert!(is_out_of_range(decode_v1::<Update>(&v1_delete_set(client))));
        }
    }

    #[test]
    fn v2_client_ids_are_checked() {
        let block = |client| v2(client, &[1, 1, 0, 0]);
        let delete_set = |client| v2(5, &with_client(&[0, 1], client, &[1, 0, 0]));
        for client in [5, MAX_CLIENT_ID] {
            assert!(decode_update_v2(&block(client)).is_ok());
            assert!(decode_update_v2(&delete_set(client)).is_ok());
        }
        for client in [OVER, OVER + 5] {
            assert!(is_out_of_range(decode_update_v2(&block(client))));
            assert!(is_out_of_range(decode_update_v2(&delete_set(client))));
        }
    }

    #[test]
    fn v2_round_trip_of_real_update() {
        use yrs::{updates::encoder::Encode, Doc, GetString, ReadTxn, Text, Transact};
        let doc = Doc::with_client_id(MAX_CLIENT_ID);
        let text = doc.get_or_insert_text("text");
        text.insert(&mut doc.transact_mut(), 0, "hello");
        text.remove_range(&mut doc.transact_mut(), 1, 2);
        let update = doc
            .transact()
            .encode_state_as_update_v2(&Default::default());
        let other = Doc::new();
        let decoded = decode_update_v2(&update).unwrap();
        other.transact_mut().apply_update(decoded).unwrap();
        let text = other.get_or_insert_text("text");
        assert_eq!(text.get_string(&other.transact()), "hlo");
        let v1 = doc
            .transact()
            .encode_state_as_update_v1(&Default::default());
        assert!(decode_v1::<Update>(&v1).is_ok());
        assert_eq!(Update::decode_v1(&v1).unwrap().encode_v1(), v1);
    }

    #[test]
    fn awareness_client_ids_are_checked() {
        let update = |client| with_client(&[1], client, b"\0\x04null");
        assert!(check_awareness_client_ids(&update(MAX_CLIENT_ID)).is_ok());
        assert!(is_out_of_range(check_awareness_client_ids(&update(
            OVER + 5
        ))));
        assert!(check_awareness_client_ids(&[0xff]).is_ok());
    }
}
