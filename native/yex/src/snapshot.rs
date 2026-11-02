//! Snapshot NIFs. The codec itself lives in `yex_core::snapshot`.

use rustler::{Binary, Encoder, Env, NifResult, Term};

pub use yex_core::snapshot::{encode_state_from_snapshot, write_snapshot};

use crate::{
    atoms,
    doc::{NifSnapshot, SnapshotRef},
    wire,
    wrap::SliceIntoBinary,
};

/// Decodes snapshot bytes into a `Yex.Snapshot` that is not bound to a document.
fn decode<'a>(env: Env<'a>, bytes: Binary, v2: bool) -> NifResult<Term<'a>> {
    let snapshot = wire::snapshot(bytes.as_slice(), v2)?;
    Ok((
        atoms::ok(),
        NifSnapshot {
            doc: None,
            reference: SnapshotRef::new(snapshot),
        },
    )
        .encode(env))
}

/// `Yex.Snapshot.decode_v1/1`: reads lib0 v1 snapshot bytes.
#[rustler::nif]
fn snapshot_decode_v1<'a>(env: Env<'a>, bytes: Binary) -> NifResult<Term<'a>> {
    decode(env, bytes, false)
}

/// `Yex.Snapshot.decode_v2/1`: reads lib0 v2 snapshot bytes.
#[rustler::nif]
fn snapshot_decode_v2<'a>(env: Env<'a>, bytes: Binary) -> NifResult<Term<'a>> {
    decode(env, bytes, true)
}

/// `Yex.Snapshot.encode_v1/1`: rewrites `reference` in canonical yjs order.
#[rustler::nif]
fn snapshot_encode_v1(env: Env<'_>, snapshot: SnapshotRef) -> Term<'_> {
    let bytes = write_snapshot(&snapshot.0, false);
    (atoms::ok(), SliceIntoBinary::new(bytes.as_slice())).encode(env)
}

/// `Yex.Snapshot.encode_v2/1`: writes the snapshot in yjs v2 format.
#[rustler::nif]
fn snapshot_encode_v2(env: Env<'_>, snapshot: SnapshotRef) -> Term<'_> {
    let bytes = write_snapshot(&snapshot.0, true);
    (atoms::ok(), SliceIntoBinary::new(bytes.as_slice())).encode(env)
}
