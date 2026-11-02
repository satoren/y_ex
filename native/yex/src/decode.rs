use std::panic::{catch_unwind, AssertUnwindSafe};

use yrs::encoding::read::Error as ReadError;
use yrs::error::UpdateError;
use yrs::updates::decoder::Decode;
use yrs::Update;

use crate::error::Error;

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

pub fn decode_update_v2(bytes: &[u8]) -> Result<Update, Error> {
    catch_decode_v2(|| Update::decode_v2(bytes))
}

/// Runs `TransactionMut::apply_update` and turns a panic inside yrs into an encoding error,
/// the same way `catch_decode_v2` does for decoding.
///
/// yrs 0.28 `apply_update` can panic (index out of bounds) while integrating an update that
/// decoded cleanly but is internally inconsistent: for example a `WeakLink` whose quoted
/// range points past the content of the block it references, where `ItemContent::splice`
/// calls `split_at` with an out-of-range offset (y-crdt/y-crdt#733). Without this guard such
/// a crafted remote update unwinds across the NIF boundary and crashes the caller (for
/// example a `Yex.Sync.SharedDoc`/`Yex.DocServer` worker applying a `sync_update`) instead of
/// returning `{:error, {:encoding_exception, _}}` as the apply functions document.
///
/// The document stays readable and writable after a caught panic, and a transaction left
/// open across it commits cleanly; any blocks integrated before the panic are bounded to
/// what the sender could also have sent as a valid update. This keeps malformed remote input
/// on the error path until yrs validates the offending fields itself.
pub fn catch_apply(apply: impl FnOnce() -> Result<(), UpdateError>) -> Result<(), Error> {
    match catch_unwind(AssertUnwindSafe(apply)) {
        Ok(result) => result.map_err(Error::from),
        Err(_) => Err(Error::from(ReadError::Custom(
            "malformed update: applying it panicked".to_string(),
        ))),
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
            catch_apply(|| txn.apply_update(update))
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
        assert!(catch_apply(|| txn.apply_update(update)).is_ok());
    }
}
