//! `yex_core::wire` with errors in this crate's [Error], so NIFs can use `?` on them.
//! See that module for what each function checks.

use yex_core::wire as core;
use yrs::sync::awareness::AwarenessUpdate;
use yrs::updates::decoder::DecoderV2;
use yrs::{Snapshot, StateVector, StickyIndex, TransactionMut, Update};

use crate::error::Error;

pub use core::{guard, message_decoder_v1};

macro_rules! adapt {
    ($($name:ident($($arg:ident: $ty:ty),*) -> $ret:ty;)*) => {
        $(
            pub fn $name($($arg: $ty),*) -> Result<$ret, Error> {
                core::$name($($arg),*).map_err(Error::from)
            }
        )*
    };
}

adapt! {
    update_v1(bytes: &[u8]) -> Update;
    update_v1_exact(bytes: &[u8]) -> Update;
    update_v2(bytes: &[u8]) -> Update;
    apply(txn: &mut TransactionMut, update: Update) -> ();
    merge_updates_v1(updates: &[&[u8]]) -> Vec<u8>;
    merge_updates_v2(updates: &[&[u8]]) -> Vec<u8>;
    diff_update_v1(update: &[u8], state_vector: &[u8]) -> Vec<u8>;
    diff_update_v2(update: &[u8], state_vector: &[u8]) -> Vec<u8>;
    state_vector_v1(bytes: &[u8]) -> StateVector;
    state_vector_v1_exact(bytes: &[u8]) -> StateVector;
    state_vector_v2(bytes: &[u8]) -> StateVector;
    sticky_index_v1(bytes: &[u8]) -> StickyIndex;
    sticky_index_v2(bytes: &[u8]) -> StickyIndex;
    snapshot(bytes: &[u8], v2: bool) -> Snapshot;
    awareness_update_v1(bytes: &[u8]) -> AwarenessUpdate;
    message_decoder_v2(bytes: &[u8]) -> DecoderV2<'_>;
}
