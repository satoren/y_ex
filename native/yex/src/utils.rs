use crate::{atoms, wrap::SliceIntoBinary};
use rustler::{types::atom::nil, Encoder, Env, OwnedBinary, Term};

/// Converts a transaction origin to an Erlang term.
///
/// Origins set from Elixir are external term format and decode back to the original
/// term. Any other origin comes from yrs itself, where only the undo manager sets one
/// (on its undo and redo transactions), so it is returned as `{:undo_manager, bytes}`.
/// A transaction without an origin gives `nil`. A decode must consume the whole origin,
/// because `binary_to_term` tolerates trailing bytes (on 32-bit targets an undo manager
/// pointer starting with byte 131 would otherwise decode as a term).
pub fn origin_to_term<'a>(
    env: &mut Env<'a>,
    origin: std::option::Option<&yrs::Origin>,
) -> Term<'a> {
    match origin {
        None => nil().encode(*env),
        Some(origin) => match env.binary_to_term(origin.as_ref()) {
            Some((term, size)) if size == origin.as_ref().len() => term,
            _ => (atoms::undo_manager(), SliceIntoBinary::new(origin.as_ref())).encode(*env),
        },
    }
}
/// Converts an Erlang term to an Origin binary.
///
/// # Arguments
/// * `term` - Erlang term to convert
///
/// # Returns
/// Returns Some(OwnedBinary) if the term is not nil, None otherwise.
pub(crate) fn term_to_origin_binary(term: Term<'_>) -> Option<OwnedBinary> {
    if nil().eq(&term) {
        None
    } else {
        Some(term.to_binary())
    }
}

// Normalizes the index for insertion into a collection of given length.
/// Negative indices count from the end of the collection.
/// capped to be within [0, len].
/// # Arguments
/// * `len` - Length of the collection
/// * `index` - Index to normalize
/// # Returns
/// Returns a normalized index as u32.
pub(crate) fn normalize_index_for_insert(len: u32, index: i64) -> u32 {
    if index < 0 {
        ((len as i64 + index + 1).clamp(0, len as i64))
            .try_into()
            .unwrap_or(0)
    } else {
        (index.clamp(0, len as i64)).try_into().unwrap_or(0)
    }
}

/// Normalizes the index for accessing a collection of given length.
/// Negative indices count from the end of the collection.
/// # Arguments
/// * `len` - Length of the collection
/// * `index` - Index to normalize
/// # Returns
/// Returns a normalized index as u32.  
pub(crate) fn normalize_index(len: u32, index: i64) -> u32 {
    if index < 0 {
        (len as i64 + index).try_into().unwrap_or(u32::MAX)
    } else {
        index.try_into().unwrap_or(u32::MAX)
    }
}

/// Caps the given index and length to be within the bounds of the target length.
/// If the resulting length is zero, returns None.
/// # Arguments
/// * `target_len` - Length of the target collection
/// * `index_i64` - Index to normalize
/// * `length` - Length to cap
/// # Returns
/// Returns Some((normalized_index, capped_length)) or None if the length is zero.
pub(crate) fn capped_index_and_length(
    target_len: u32,
    index_i64: i64,
    length: u32,
) -> Option<(u32, u32)> {
    let index = normalize_index(target_len, index_i64);
    let remaining = target_len.saturating_sub(index);
    let actual_length = length.min(remaining);
    if actual_length == 0 {
        None
    } else {
        Some((index, actual_length))
    }
}

#[test]
fn test_capped_index_and_length() {
    assert_eq!(capped_index_and_length(10, 5, 3), Some((5, 3)));
    assert_eq!(capped_index_and_length(7, 5, 3), Some((5, 2)));
    assert_eq!(capped_index_and_length(1, 5, 3), None);
    assert_eq!(capped_index_and_length(1, -1, 3), Some((0, 1)));
}
