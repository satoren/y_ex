use std::panic::{catch_unwind, AssertUnwindSafe};

use yrs::encoding::read::Error as ReadError;
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
}
