//! The one place where bytes from outside the VM are decoded and applied.
//!
//! Updates, state vectors, sticky indexes, snapshots, awareness updates and sync messages
//! can come from a remote peer, so every decode, merge, diff and apply of them goes
//! through a function here. Each one does the same three things:
//!
//! 1. runs the yrs call under `catch_unwind` ([guard]), so a panic inside yrs becomes
//!    `{:error, {:encoding_exception, msg}}` instead of unwinding into the NIF caller;
//! 2. applies the checks yrs 0.28 leaves out (trailing bytes for v1, the 53-bit client id
//!    range for awareness);
//! 3. maps every failure to [Error::Encoding].
//!
//! `clippy.toml` disallows the raw yrs entry points everywhere else, so a new NIF cannot
//! skip this module by accident.
#![allow(clippy::disallowed_methods)]

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

use yrs::encoding::read::{Cursor, Error as ReadError, Read};
use yrs::sync::awareness::{AwarenessUpdate, AwarenessUpdateEntry};
use yrs::updates::decoder::{Decode, DecoderV1, DecoderV2};
use yrs::updates::encoder::Encode;
use yrs::{ClientID, Snapshot, StateVector, StickyIndex, TransactionMut, Update};

use crate::error::WireError as Error;
use crate::MAX_CLIENT_ID;

/// Runs `f` and turns a panic inside it into an encoding error naming `what`.
///
/// yrs 0.28 panics on some malformed input instead of returning an error, for example:
///
/// - `DecoderV2::read_usize` checks the input length once before its varint loop, so a
///   column length whose continuation bits run to the end of the input (`<<0, 128>>`)
///   indexes past the buffer. Every v2 decode reads those lengths first.
/// - `TransactionMut::apply_update` can index out of bounds while integrating an update
///   that decoded cleanly but is internally inconsistent, such as a `WeakLink` whose quoted
///   range points past the referenced block (y-crdt/y-crdt#733).
///
/// After a caught apply panic the document stays readable and writable, and a transaction
/// left open across it commits cleanly; blocks integrated before the panic are bounded to
/// what the sender could also have sent as a valid update.
///
/// `E` lets a caller keep its own error type for work done inside the guard.
pub fn guard<T, E: From<Error>>(what: &str, f: impl FnOnce() -> Result<T, E>) -> Result<T, E> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| {
        Err(E::from(Error::Encoding(ReadError::Custom(format!(
            "malformed {what}: yrs panicked"
        )))))
    })
}

fn custom(message: String) -> Error {
    Error::Encoding(ReadError::Custom(message))
}

/// Decodes `T` from v1 bytes and rejects input left unread. A v2 payload starts with a
/// zero byte, which the v1 decoder reads as an empty update or state vector before
/// stopping, so the leftover bytes are what tell a v2 value passed by mistake from a real
/// empty one.
fn decode_v1_exact<T: Decode>(bytes: &[u8], what: &str) -> Result<T, Error> {
    guard(what, || {
        let mut decoder = DecoderV1::from(bytes);
        let decoded = T::decode(&mut decoder)?;
        if decoder.read_u8().is_ok() {
            return Err(custom(format!("{what} has trailing bytes")));
        }
        Ok(decoded)
    })
}

// Updates

/// A v1 update, reading only as far as the update goes (what `Yex.apply_update/2` has always
/// accepted).
pub fn update_v1(bytes: &[u8]) -> Result<Update, Error> {
    guard("v1 update", || Ok(Update::decode_v1(bytes)?))
}

/// A v1 update that must span all of `bytes` (the doc-free update utilities).
pub fn update_v1_exact(bytes: &[u8]) -> Result<Update, Error> {
    decode_v1_exact(bytes, "update")
}

pub fn update_v2(bytes: &[u8]) -> Result<Update, Error> {
    guard("v2 update", || Ok(Update::decode_v2(bytes)?))
}

/// Integrates a decoded update into `txn`.
pub fn apply(txn: &mut TransactionMut, update: Update) -> Result<(), Error> {
    guard("update", || Ok(txn.apply_update(update)?))
}

pub fn merge_updates_v1(updates: &[&[u8]]) -> Result<Vec<u8>, Error> {
    guard("v1 update", || {
        Ok(yrs::merge_updates_v1(updates.iter().copied())?)
    })
}

pub fn merge_updates_v2(updates: &[&[u8]]) -> Result<Vec<u8>, Error> {
    guard("v2 update", || {
        let updates = updates
            .iter()
            .map(|update| Ok(Update::decode_v2(update)?))
            .collect::<Result<Vec<_>, Error>>()?;
        Ok(Update::merge_updates(updates).encode_v2())
    })
}

/// The part of a v1 update that `state_vector` (v1) does not cover.
pub fn diff_update_v1(update: &[u8], state_vector: &[u8]) -> Result<Vec<u8>, Error> {
    // yrs diff_updates_v1 decodes both inputs without a leftover-byte check, so a v2
    // update or state vector would come back as an empty or meaningless diff. Update has
    // no public diff method, so the inputs are validated here and decoded again by yrs.
    state_vector_v1_exact(state_vector)?;
    update_v1_exact(update)?;
    guard("v1 update", || {
        Ok(yrs::diff_updates_v1(update, state_vector)?)
    })
}

/// The part of a v2 update that `state_vector` (v1, as in yjs) does not cover.
pub fn diff_update_v2(update: &[u8], state_vector: &[u8]) -> Result<Vec<u8>, Error> {
    // yrs diff_updates_v2 expects the yrs v2 framing of the state vector and
    // Update::encode_diff is not public, so the (small) state vector is re-framed.
    let state_vector = state_vector_v1_exact(state_vector)?.encode_v2();
    guard("v2 update", || {
        Ok(yrs::diff_updates_v2(update, &state_vector)?)
    })
}

// State vectors

/// A v1 state vector, reading only as far as it goes (the doc encoders and sync step 1).
pub fn state_vector_v1(bytes: &[u8]) -> Result<StateVector, Error> {
    guard("v1 state vector", || Ok(StateVector::decode_v1(bytes)?))
}

/// A v1 state vector that must span all of `bytes`. The yrs v2 framing of a state vector
/// (`encode_state_vector_v2/1`) starts with a zero byte too, which the v1 decoder would
/// otherwise read as the empty state vector.
pub fn state_vector_v1_exact(bytes: &[u8]) -> Result<StateVector, Error> {
    decode_v1_exact(bytes, "state vector")
}

pub fn state_vector_v2(bytes: &[u8]) -> Result<StateVector, Error> {
    guard("v2 state vector", || Ok(StateVector::decode_v2(bytes)?))
}

// Other values

pub fn sticky_index_v1(bytes: &[u8]) -> Result<StickyIndex, Error> {
    guard("v1 sticky index", || Ok(StickyIndex::decode_v1(bytes)?))
}

pub fn sticky_index_v2(bytes: &[u8]) -> Result<StickyIndex, Error> {
    guard("v2 sticky index", || Ok(StickyIndex::decode_v2(bytes)?))
}

pub fn snapshot(bytes: &[u8], v2: bool) -> Result<Snapshot, Error> {
    guard("snapshot", || {
        Ok(crate::snapshot::read_snapshot(bytes, v2)?)
    })
}

/// A v1 awareness update, rejecting client ids of 2^53 or more.
///
/// yrs 0.28 `AwarenessUpdate::decode` passes the raw `u64` to `ClientID::new`, which only
/// debug-asserts the 53-bit range and masks the high bits away in release builds. A remote
/// entry for client `2^53 + n` would then overwrite or remove the state of client `n`,
/// including the local one. The wire format is `len, (client, clock, json)*`, as in yjs.
pub fn awareness_update_v1(bytes: &[u8]) -> Result<AwarenessUpdate, Error> {
    guard("awareness update", || {
        let mut cursor = Cursor::new(bytes);
        let len: usize = cursor.read_var()?;
        let mut clients = HashMap::new();
        // `len` comes from the network: reserve fallibly, as yrs does.
        clients.try_reserve(len).map_err(ReadError::from)?;
        for _ in 0..len {
            let client: u64 = cursor.read_var()?;
            if client > MAX_CLIENT_ID {
                return Err(custom(format!(
                    "awareness client id {client} is out of range 0..{MAX_CLIENT_ID}"
                )));
            }
            let clock: u32 = cursor.read_var()?;
            let json: Arc<str> = cursor.read_string()?.into();
            clients.insert(ClientID::new(client), AwarenessUpdateEntry { clock, json });
        }
        Ok(AwarenessUpdate { clients })
    })
}

/// A lib0 v1 decoder over a sync protocol message. Reading from it can still panic inside
/// yrs, so run the whole read under [guard].
pub fn message_decoder_v1(bytes: &[u8]) -> DecoderV1<'_> {
    DecoderV1::new(Cursor::new(bytes))
}

/// A lib0 v2 decoder over a sync protocol message. Building it reads the column lengths,
/// which can panic (see [guard]).
pub fn message_decoder_v2(bytes: &[u8]) -> Result<DecoderV2<'_>, Error> {
    guard("v2 message", || Ok(DecoderV2::new(Cursor::new(bytes))?))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::disallowed_methods)]
    use super::*;

    #[test]
    fn truncated_column_length_is_an_encoding_error() {
        for bytes in [&[0, 128][..], &[255, 255, 255][..]] {
            assert!(matches!(update_v2(bytes), Err(Error::Encoding(_))));
        }
    }

    #[test]
    fn valid_input_and_ordinary_errors_pass_through() {
        use yrs::updates::encoder::Encode;
        assert!(update_v2(&Update::new().encode_v2()).is_ok());
        assert!(matches!(update_v2(&[]), Err(Error::Encoding(_))));
    }

    // A v1 update carrying a WeakLink whose quoted range points past the referenced block's
    // content. It decodes cleanly but `apply_update` panics in `ItemContent::splice`
    // (`mid > len`) while materializing the link (y-crdt/y-crdt#733). Minimized from a fuzzer
    // corpus of updates that contain a quoted value.
    const WEAK_LINK_PANIC_UPDATE_V1: &[u8] = &[
        1, 18, 1, 0, 4, 1, 1, 116, 1, 104, 132, 1, 0, 1, 101, 129, 1, 1, 2, 129, 1, 3, 1, 132, 1,
        4, 6, 32, 119, 111, 114, 108, 100, 198, 1, 0, 1, 1, 4, 98, 111, 108, 100, 4, 116, 114, 117,
        101, 198, 1, 3, 1, 4, 4, 98, 111, 108, 100, 4, 110, 117, 108, 108, 1, 1, 1, 97, 1, 136, 1,
        13, 2, 125, 2, 125, 3, 199, 1, 13, 1, 14, 1, 40, 0, 1, 16, 1, 107, 1, 119, 1, 118, 39, 1,
        1, 111, 1, 97, 0, 39, 1, 1, 109, 4, 108, 105, 110, 107, 7, 1, 1, 15, 1, 14, 39, 1, 1, 109,
        2, 4, 7, 1, 1, 120, 3, 1, 112, 7, 0, 1, 21, 6, 4, 0, 1, 22, 3, 97, 98, 99, 41, 1, 1, 109,
        3, 100, 111, 99, 36, 57, 48, 99, 51, 52, 54, 54, 99, 45, 56, 50, 54, 49, 45, 52, 56, 54,
        98, 45, 57, 101, 57, 51, 45, 100, 56, 55, 98, 50, 57, 52, 98, 99, 53, 51, 100, 118, 4, 2,
        103, 99, 120, 8, 101, 110, 99, 111, 100, 105, 110, 103, 125, 1, 8, 97, 117, 116, 111, 76,
        111, 97, 100, 121, 10, 115, 104, 111, 117, 108, 100, 76, 111, 97, 100, 120, 1, 1, 2, 2, 3,
        13, 1,
    ];

    #[test]
    fn apply_panic_becomes_an_encoding_error_and_leaves_the_doc_usable() {
        use yrs::{Doc, GetString, ReadTxn, StateVector, Text, Transact, Update};

        let update = Update::decode_v1(WEAK_LINK_PANIC_UPDATE_V1).expect("update decodes");

        let doc = Doc::new();
        let text = doc.get_or_insert_text("pre");
        {
            let mut txn = doc.transact_mut();
            text.insert(&mut txn, 0, "hello");
        }

        // The crafted update makes `apply_update` panic; the guard turns it into an error.
        let result = {
            let mut txn = doc.transact_mut();
            apply(&mut txn, update)
        };
        assert!(matches!(result, Err(Error::Encoding(_))));

        // The document is still readable and writable afterwards.
        {
            let txn = doc.transact();
            let _ = txn.encode_state_as_update_v1(&StateVector::default());
        }
        {
            let mut txn = doc.transact_mut();
            text.insert(&mut txn, 0, "X");
            assert_eq!(text.get_string(&txn), "Xhello");
        }
    }

    #[test]
    fn catch_apply_passes_a_good_update_through() {
        use yrs::{Doc, ReadTxn, Text, Transact, Update};

        let source = Doc::new();
        let text = source.get_or_insert_text("t");
        {
            let mut txn = source.transact_mut();
            text.insert(&mut txn, 0, "abc");
        }
        let bytes = source
            .transact()
            .encode_state_as_update_v1(&yrs::StateVector::default());

        let doc = Doc::new();
        let _ = doc.get_or_insert_text("t");
        let update = Update::decode_v1(&bytes).unwrap();
        let mut txn = doc.transact_mut();
        assert!(apply(&mut txn, update).is_ok());
    }

    /// Every entry point returns, never unwinds, on arbitrary bytes. Uses a fixed xorshift
    /// seed so a failure reproduces.
    #[test]
    fn no_entry_point_unwinds_on_garbage() {
        use std::panic;
        use yrs::{Doc, Transact};

        let mut state: u64 = 0x9e37_79b9_7f4a_7c15;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let quiet = panic::take_hook();
        panic::set_hook(Box::new(|_| {}));
        let result = panic::catch_unwind(panic::AssertUnwindSafe(|| {
            for _ in 0..200 {
                let len = (next() % 48) as usize;
                let bytes: Vec<u8> = (0..len).map(|_| next() as u8).collect();
                let _ = update_v1(&bytes);
                let _ = update_v1_exact(&bytes);
                let _ = update_v2(&bytes);
                let _ = state_vector_v1(&bytes);
                let _ = state_vector_v1_exact(&bytes);
                let _ = state_vector_v2(&bytes);
                let _ = sticky_index_v1(&bytes);
                let _ = sticky_index_v2(&bytes);
                let _ = snapshot(&bytes, false);
                let _ = snapshot(&bytes, true);
                let _ = awareness_update_v1(&bytes);
                let _ = message_decoder_v2(&bytes);
                let _ = merge_updates_v1(&[&bytes, &bytes]);
                let _ = merge_updates_v2(&[&bytes, &bytes]);
                let _ = diff_update_v1(&bytes, &[0]);
                let _ = diff_update_v2(&bytes, &[0]);
                for decoded in [update_v1(&bytes), update_v2(&bytes)].into_iter().flatten() {
                    let doc = Doc::new();
                    let mut txn = doc.transact_mut();
                    let _ = apply(&mut txn, decoded);
                }
            }
        }));
        panic::set_hook(quiet);
        assert!(result.is_ok(), "a wire entry point unwound");
    }
}
