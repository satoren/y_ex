//! The decoders for everything other than updates: state vectors, sticky indexes,
//! snapshots, awareness updates and v2 sync message framing.
#![no_main]

mod common;
use common::quiet_caught_panics;

use libfuzzer_sys::fuzz_target;
use yex_core::wire;

fuzz_target!(|data: &[u8]| {
    quiet_caught_panics();
    let _ = wire::state_vector_v1(data);
    let _ = wire::state_vector_v1_exact(data);
    let _ = wire::state_vector_v2(data);
    let _ = wire::sticky_index_v1(data);
    let _ = wire::sticky_index_v2(data);
    let _ = wire::snapshot(data, false);
    let _ = wire::snapshot(data, true);
    let _ = wire::awareness_update_v1(data);
    let _ = wire::message_decoder_v2(data);
});
