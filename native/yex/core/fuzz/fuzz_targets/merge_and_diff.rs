//! Merge and diff, which decode their inputs again inside yrs. The input is split at its
//! first byte into an update and a second update / state vector.
#![no_main]

mod common;
use common::quiet_caught_panics;

use libfuzzer_sys::fuzz_target;
use yex_core::wire;

fuzz_target!(|data: &[u8]| {
    quiet_caught_panics();
    let Some((&split, rest)) = data.split_first() else {
        return;
    };
    let (a, b) = rest.split_at((split as usize).min(rest.len()));
    let _ = wire::merge_updates_v1(&[a, b]);
    let _ = wire::merge_updates_v2(&[a, b]);
    let _ = wire::diff_update_v1(a, b);
    let _ = wire::diff_update_v2(a, b);
});
