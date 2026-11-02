//! The part of the y_ex NIF that does not depend on rustler.
//!
//! Code here works on yrs types only, so it builds and tests with a plain `cargo test`
//! and can be fuzzed (see `fuzz/`). The `yex` crate next to it turns Erlang terms into
//! these types and back.

pub mod error;
pub mod snapshot;
pub mod wire;

pub use error::WireError;

/// Largest client id yjs and yrs accept (`2^53 - 1`).
pub const MAX_CLIENT_ID: u64 = (1 << 53) - 1;
