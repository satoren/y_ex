//! Decode a v1 update and apply it to a fresh document, as `Yex.apply_update/2` does.
//! A panic that escapes `wire` (and so would reach the NIF caller) is a finding.
#![no_main]

mod common;
use common::quiet_caught_panics;

use libfuzzer_sys::fuzz_target;
use yex_core::wire;
use yrs::{Doc, Transact};

fuzz_target!(|data: &[u8]| {
    quiet_caught_panics();
    let _ = wire::update_v1_exact(data);
    if let Ok(update) = wire::update_v1(data) {
        let doc = Doc::new();
        let mut txn = doc.transact_mut();
        let _ = wire::apply(&mut txn, update);
    }
});
