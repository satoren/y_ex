//! Snapshot codec matching yjs `encodeSnapshot` / `encodeSnapshotV2` byte for byte.
//!
//! yrs `Snapshot::encode_v2` frames the snapshot as a full update (feature byte plus nine
//! column buffers), which yjs `decodeSnapshotV2` cannot read, and yrs writes clients in
//! map order where yjs writes them in descending order. Both directions are implemented
//! here so every snapshot y_ex produces has one canonical byte form.

use rustler::{Binary, Encoder, Env, NifResult, Term};
use yrs::branch::{Branch, BranchPtr};
use yrs::encoding::read::{Cursor, Error as ReadError, Read};
use yrs::encoding::write::Write;
use yrs::types::text::YChange;
use yrs::types::TypeRef;
use yrs::updates::encoder::Encoder as UpdatesEncoder;
use yrs::{ClientID, IdSet, ReadTxn, Snapshot, StateVector, Text, TextRef, TransactionMut, ID};

use crate::{
    atoms,
    doc::{NifSnapshot, SnapshotRef},
    error::Error,
    wrap::SliceIntoBinary,
};

/// Largest client id yjs and yrs accept (53 bits).
const MAX_CLIENT: u64 = (1 << 53) - 1;

/// Writes `snapshot` as lib0 v1 (`v2 == false`) or v2 snapshot bytes.
///
/// Delete set and state vector are written client-descending. Delete set ranges must be
/// sorted, merged and non-empty, which holds for snapshots taken from a store and for
/// snapshots read by [read_snapshot]. State vector entries with clock 0 are skipped.
pub fn write_snapshot(snapshot: &Snapshot, v2: bool) -> Vec<u8> {
    let mut buf = Vec::new();

    let mut clients: Vec<_> = snapshot.delete_set.iter().collect();
    clients.sort_by(|a, b| b.0.cmp(a.0));
    buf.write_var(clients.len() as u32);
    for (client, ranges) in clients {
        buf.write_var(client.get());
        buf.write_var(ranges.len() as u32);
        let mut cursor = 0u32;
        for range in ranges.iter() {
            let len = range.end - range.start;
            if v2 {
                buf.write_var(range.start - cursor);
                buf.write_var(len - 1);
                cursor = range.end;
            } else {
                buf.write_var(range.start);
                buf.write_var(len);
            }
        }
    }

    let mut sv: Vec<_> = snapshot
        .state_map
        .iter()
        .filter(|(_, &clock)| clock > 0)
        .collect();
    sv.sort_by(|a, b| b.0.cmp(a.0));
    buf.write_var(sv.len() as u32);
    for (client, clock) in sv {
        buf.write_var(client.get());
        buf.write_var(*clock);
    }
    buf
}

/// Reads lib0 v1 (`v2 == false`) or v2 snapshot bytes.
///
/// Ranges are inserted through `IdSet::insert`, which sorts and merges them; empty ranges
/// are dropped, duplicate clients merge, state vector entries keep the highest clock and
/// clock-0 entries are dropped. Trailing bytes are ignored, as in yjs.
pub fn read_snapshot(bytes: &[u8], v2: bool) -> Result<Snapshot, ReadError> {
    let mut cursor = Cursor::new(bytes);

    let mut delete_set = IdSet::new();
    let clients: u32 = cursor.read_var()?;
    for _ in 0..clients {
        let client = read_client(&mut cursor)?;
        let ranges: u32 = cursor.read_var()?;
        let mut position = 0u32;
        for _ in 0..ranges {
            let (start, len) = if v2 {
                let diff: u32 = cursor.read_var()?;
                let len_minus_one: u32 = cursor.read_var()?;
                let start = position
                    .checked_add(diff)
                    .ok_or(ReadError::UnexpectedValue)?;
                let len = len_minus_one
                    .checked_add(1)
                    .ok_or(ReadError::UnexpectedValue)?;
                (start, len)
            } else {
                (cursor.read_var()?, cursor.read_var()?)
            };
            let end = start.checked_add(len).ok_or(ReadError::UnexpectedValue)?;
            position = end;
            if len > 0 {
                delete_set.insert(ID::new(client, start), len);
            }
        }
    }

    let mut state_map = StateVector::default();
    let entries: u32 = cursor.read_var()?;
    for _ in 0..entries {
        let client = read_client(&mut cursor)?;
        let clock: u32 = cursor.read_var()?;
        if clock > 0 {
            state_map.set_max(client, clock);
        }
    }

    Ok(Snapshot::new(state_map, delete_set))
}

fn read_client(cursor: &mut Cursor) -> Result<ClientID, ReadError> {
    let client: u64 = cursor.read_var()?;
    if client > MAX_CLIENT {
        return Err(ReadError::UnexpectedValue);
    }
    Ok(ClientID::new(client))
}

/// Keeps only the delete set clients this store has blocks for.
///
/// `Text::diff_range` panics on a delete set client the store does not know
/// (`get_client(..).unwrap()` in yrs `id_set::Blocks::next`). Items of such clients are
/// not in the store, so dropping them cannot change the visibility of any walked item.
/// In the common case, where every delete set client is known, the snapshot is returned
/// as is.
pub fn known_clients_only(snapshot: Snapshot, local: &StateVector) -> Snapshot {
    if snapshot
        .delete_set
        .client_ids()
        .all(|c| local.contains_client(&c))
    {
        return snapshot;
    }
    let Snapshot {
        state_map,
        delete_set,
    } = snapshot;
    let mut known = IdSet::new();
    for client in delete_set.client_ids() {
        if local.contains_client(&client) {
            if let Some(range) = delete_set.get(&client) {
                known.insert_range(client, range.clone());
            }
        }
    }
    Snapshot::new(state_map, known)
}

/// `ReadTxn::encode_state_from_snapshot` without two yrs 0.28 bugs.
///
/// When a snapshot clock falls inside a block, `Store::write_blocks_to` encodes the block's
/// left part with the `HAS_RIGHT_ORIGIN` info bit set but without the right origin
/// (`ItemSlice::encode` writes it only for a slice that reaches the end of its block), so
/// the update is corrupt. yjs splits those blocks first (`splitSnapshotAffectedStructs`).
/// The only public yrs call that splits blocks at a snapshot's clocks is
/// `Text::diff_range`; it runs here on a detached branch, so it walks no items. The split
/// leaves the content and state vector unchanged and emits no update.
///
/// When a client's first blocks are missing, yrs integrates the later ones behind a gap
/// and reports clock 0 for that client; `Store::write_blocks_to` then computes
/// `find_index(clock - 1)` and panics. Clients at local clock 0 have nothing encodable
/// from clock 0 onwards, so they are left out of the state map.
pub fn encode_state_from_snapshot<E: UpdatesEncoder>(
    txn: &mut TransactionMut,
    snapshot: Snapshot,
    encoder: &mut E,
) -> Result<(), yrs::error::Error> {
    // Fail before the split below mutates the store.
    if !txn.doc().skip_gc() {
        return Err(yrs::error::Error::Gc);
    }
    let local = txn.state_vector();
    let state_map: StateVector = snapshot
        .state_map
        .iter()
        .filter(|(client, _)| local.get(client) > 0)
        .map(|(client, clock)| (*client, *clock))
        .collect();
    let detached = Branch::new(TypeRef::Text);
    let split = Snapshot::new(state_map, IdSet::default());
    TextRef::from(BranchPtr::from(&*detached)).diff_range(
        txn,
        Some(&split),
        None,
        YChange::identity,
    );
    let Snapshot { state_map, .. } = split;
    let snapshot = Snapshot::new(state_map, snapshot.delete_set);
    txn.encode_state_from_snapshot(&snapshot, encoder)
}

fn decode<'a>(env: Env<'a>, bytes: Binary, v2: bool) -> NifResult<Term<'a>> {
    let snapshot = read_snapshot(bytes.as_slice(), v2).map_err(Error::from)?;
    Ok((
        atoms::ok(),
        NifSnapshot {
            doc: None,
            reference: SnapshotRef::new(snapshot),
        },
    )
        .encode(env))
}

#[rustler::nif]
fn snapshot_decode_v1<'a>(env: Env<'a>, bytes: Binary) -> NifResult<Term<'a>> {
    decode(env, bytes, false)
}

#[rustler::nif]
fn snapshot_decode_v2<'a>(env: Env<'a>, bytes: Binary) -> NifResult<Term<'a>> {
    decode(env, bytes, true)
}

#[rustler::nif]
fn snapshot_encode_v1(env: Env<'_>, snapshot: SnapshotRef) -> Term<'_> {
    let bytes = write_snapshot(&snapshot.0, false);
    (atoms::ok(), SliceIntoBinary::new(bytes.as_slice())).encode(env)
}

#[rustler::nif]
fn snapshot_encode_v2(env: Env<'_>, snapshot: SnapshotRef) -> Term<'_> {
    let bytes = write_snapshot(&snapshot.0, true);
    (atoms::ok(), SliceIntoBinary::new(bytes.as_slice())).encode(env)
}

#[cfg(test)]
mod tests {
    use super::*;
    use yrs::updates::decoder::Decode;
    use yrs::updates::encoder::{EncoderV1, EncoderV2};
    use yrs::{Array, Doc, GetString, Map, Options, ReadTxn, Text, Transact, Update};

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    // Generated by yjs 13.6 (see test/snapshot_test.exs for the generating script).
    const S1_V1: &str = "00010103";
    const S1_V2: &str = "00010103";
    const S2_V1: &str = "0101010101010106";
    const S2_V2: &str = "0101010100010106";
    const MULTI_V1: &str = "0205010001010101010205020106";
    const MULTI_V2: &str = "0205010000010101000205020106";
    const UPDATE_A: &str = "010601000401047465787401618401000162840101016386010204626f6c640474727565840103016486010404626f6c64046e756c6c0101010101";
    const UPDATE_B: &str = "02020500440100017ac405000100017a0601000401047465787401618401000162840101016386010204626f6c640474727565840103016486010404626f6c64046e756c6c020501000101010101";

    fn doc(client: u64) -> Doc {
        Doc::with_options(Options {
            client_id: ClientID::new(client),
            skip_gc: true,
            ..Options::default()
        })
    }

    #[test]
    fn encodes_a_snapshot_clock_inside_a_block() {
        // "X" and "Y" merge into one block with right origin "a"; the snapshot ends
        // between them.
        let a = doc(1);
        let t = a.get_or_insert_text("text");
        t.insert(&mut a.transact_mut(), 0, "abc");
        t.insert(&mut a.transact_mut(), 0, "X");
        let s = a.transact().snapshot();
        t.insert(&mut a.transact_mut(), 1, "Y");

        let mut v1 = EncoderV1::new();
        encode_state_from_snapshot(&mut a.transact_mut(), s.clone(), &mut v1).unwrap();
        let mut v2 = EncoderV2::new();
        encode_state_from_snapshot(&mut a.transact_mut(), s, &mut v2).unwrap();
        for update in [
            Update::decode_v1(&v1.to_vec()).unwrap(),
            Update::decode_v2(&v2.to_vec()).unwrap(),
        ] {
            let target = Doc::new();
            let text = target.get_or_insert_text("text");
            target.transact_mut().apply_update(update).unwrap();
            assert_eq!(text.get_string(&target.transact()), "Xabc");
        }
        assert_eq!(t.get_string(&a.transact()), "XYabc");
    }

    #[test]
    fn rejects_a_store_with_gc_enabled() {
        let a = Doc::with_options(Options {
            client_id: ClientID::new(1),
            skip_gc: false,
            ..Options::default()
        });
        let t = a.get_or_insert_text("text");
        t.insert(&mut a.transact_mut(), 0, "abc");
        let s = a.transact().snapshot();
        let mut v1 = EncoderV1::new();
        let result = encode_state_from_snapshot(&mut a.transact_mut(), s, &mut v1);
        assert!(matches!(result, Err(yrs::error::Error::Gc)));
    }

    #[test]
    fn encodes_state_on_a_store_missing_a_clients_first_blocks() {
        let a = doc(1);
        a.get_or_insert_text("x")
            .insert(&mut a.transact_mut(), 0, "hello");
        let sv = a.transact().state_vector();
        a.get_or_insert_text("y")
            .insert(&mut a.transact_mut(), 0, "world");
        let later = a.transact().encode_diff_v1(&sv);

        let b = doc(2);
        b.transact_mut()
            .apply_update(Update::decode_v1(&later).unwrap())
            .unwrap();
        // the later blocks are integrated behind a gap, at reported clock 0
        assert_eq!(b.transact().state_vector().get(&ClientID::new(1)), 0);
        assert!(b
            .transact()
            .state_vector()
            .contains_client(&ClientID::new(1)));

        let snapshot = Snapshot::new(
            StateVector::from_iter([(ClientID::new(1), 10)]),
            IdSet::default(),
        );
        let mut v1 = EncoderV1::new();
        encode_state_from_snapshot(&mut b.transact_mut(), snapshot.clone(), &mut v1).unwrap();
        let mut v2 = EncoderV2::new();
        encode_state_from_snapshot(&mut b.transact_mut(), snapshot, &mut v2).unwrap();
        // client 1 is left out entirely: an empty update
        assert_eq!(v1.to_vec(), vec![0, 0]);
    }

    #[test]
    fn round_trips_yjs_bytes() {
        for (bytes, v2) in [
            (S1_V1, false),
            (S1_V2, true),
            (S2_V1, false),
            (S2_V2, true),
            (MULTI_V1, false),
            (MULTI_V2, true),
            ("0000", false),
            ("0000", true),
        ] {
            let bytes = hex(bytes);
            let snapshot = read_snapshot(&bytes, v2).unwrap();
            assert_eq!(write_snapshot(&snapshot, v2), bytes);
        }
    }

    #[test]
    fn v1_and_v2_decode_to_the_same_snapshot() {
        for (v1, v2) in [(S1_V1, S1_V2), (S2_V1, S2_V2), (MULTI_V1, MULTI_V2)] {
            assert_eq!(
                read_snapshot(&hex(v1), false).unwrap(),
                read_snapshot(&hex(v2), true).unwrap()
            );
        }
    }

    #[test]
    fn live_snapshot_matches_yjs_bytes() {
        let a = doc(1);
        a.transact_mut()
            .apply_update(Update::decode_v1(&hex(UPDATE_A)).unwrap())
            .unwrap();
        let snapshot = a.transact().snapshot();
        assert_eq!(write_snapshot(&snapshot, false), hex(S2_V1));
        assert_eq!(write_snapshot(&snapshot, true), hex(S2_V2));

        let b = doc(5);
        b.transact_mut()
            .apply_update(Update::decode_v1(&hex(UPDATE_B)).unwrap())
            .unwrap();
        let snapshot = b.transact().snapshot();
        assert_eq!(write_snapshot(&snapshot, false), hex(MULTI_V1));
        assert_eq!(write_snapshot(&snapshot, true), hex(MULTI_V2));
    }

    #[test]
    fn live_snapshot_coalesces_adjacent_deletions() {
        let d = doc(1);
        let text = d.get_or_insert_text("text");
        text.insert(&mut d.transact_mut(), 0, "abcdef");
        // two separate deletions of neighbouring runs: "bc" then "de" (now at index 1)
        text.remove_range(&mut d.transact_mut(), 1, 2);
        text.remove_range(&mut d.transact_mut(), 1, 2);
        assert_eq!(text.get_string(&d.transact()), "af");
        let snapshot = d.transact().snapshot();
        // one range [1, 5) for client 1, state vector {1: 6}
        assert_eq!(
            write_snapshot(&snapshot, false),
            vec![1, 1, 1, 1, 4, 1, 1, 6]
        );
        assert_eq!(
            write_snapshot(&snapshot, true),
            vec![1, 1, 1, 1, 3, 1, 1, 6]
        );
    }

    #[test]
    fn normalizes_ranges_and_clients() {
        // client 1: [1,2) and [2,3) -> [1,3)
        let fragmented = read_snapshot(&[1, 1, 2, 1, 1, 2, 1, 0], false).unwrap();
        let merged = read_snapshot(&[1, 1, 1, 1, 2, 0], false).unwrap();
        assert_eq!(
            write_snapshot(&fragmented, false),
            write_snapshot(&merged, false)
        );
        // the same client twice merges into one entry
        let twice = read_snapshot(&[2, 1, 1, 1, 1, 1, 1, 2, 1, 0], false).unwrap();
        assert_eq!(
            write_snapshot(&twice, false),
            write_snapshot(&merged, false)
        );
        // zero length range is dropped
        let empty = read_snapshot(&[1, 1, 1, 4, 0, 0], false).unwrap();
        assert_eq!(write_snapshot(&empty, false), vec![0, 0]);
    }

    #[test]
    fn drops_zero_clock_state_vector_entries() {
        let snapshot = read_snapshot(&[0, 1, 1, 0], false).unwrap();
        assert_eq!(write_snapshot(&snapshot, false), vec![0, 0]);
        // duplicate state vector clients keep the highest clock
        let snapshot = read_snapshot(&[0, 2, 1, 7, 1, 3], false).unwrap();
        assert_eq!(write_snapshot(&snapshot, false), vec![0, 1, 1, 7]);
    }

    #[test]
    fn rejects_malformed_input_without_panicking() {
        assert!(read_snapshot(&[], false).is_err());
        assert!(read_snapshot(&[0x80], false).is_err());
        assert!(read_snapshot(&[1], true).is_err());
        // a huge declared client count with no data behind it
        assert!(read_snapshot(&[0xff, 0xff, 0xff, 0xff, 0x0f], false).is_err());
        // v1 clock + len overflows u32
        let mut v1 = vec![1, 1, 1];
        v1.extend_from_slice(&[0xff, 0xff, 0xff, 0xff, 0x0f]);
        v1.extend_from_slice(&[0x02, 0]);
        assert!(read_snapshot(&v1, false).is_err());
        // v2 len - 1 overflows u32
        let mut v2 = vec![1, 1, 1, 0];
        v2.extend_from_slice(&[0xff, 0xff, 0xff, 0xff, 0x0f, 0]);
        assert!(read_snapshot(&v2, true).is_err());
        // client id above 53 bits
        let mut big = vec![0, 1];
        big.extend_from_slice(&[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f, 1]);
        assert!(read_snapshot(&big, false).is_err());
        // yrs-framed v2 bytes are not a yjs v2 snapshot: the leading feature byte and
        // empty column buffers read as zero clients and an empty state vector, and the
        // rest is ignored as trailing bytes, so they are misread as the empty snapshot.
        assert_eq!(
            read_snapshot(&hex("00000000000001000000000101010100010106"), true).unwrap(),
            Snapshot::default()
        );
    }

    #[test]
    fn strips_unknown_delete_set_clients() {
        let snapshot = read_snapshot(&hex(MULTI_V1), false).unwrap();
        let local = StateVector::from_iter([(ClientID::new(1), 6)]);
        let stripped = known_clients_only(snapshot, &local);
        assert_eq!(
            stripped.delete_set.client_ids().collect::<Vec<_>>(),
            vec![ClientID::new(1)]
        );
    }

    /// Update sequences for the doc shapes the fuzz test runs against, applied in order to
    /// a fresh doc with client 100. Roots used: "x", "y", "z".
    fn shapes() -> Vec<(&'static str, Vec<Vec<u8>>)> {
        let mut shapes = vec![("empty", vec![])];

        let a = doc(1);
        let x = a.get_or_insert_text("x");
        x.insert(&mut a.transact_mut(), 0, "abcdef");
        x.remove_range(&mut a.transact_mut(), 1, 2);
        x.insert(&mut a.transact_mut(), 2, "gh");
        x.remove_range(&mut a.transact_mut(), 0, 1);
        shapes.push((
            "single client",
            vec![a
                .transact()
                .encode_state_as_update_v1(&StateVector::default())],
        ));

        let b = doc(2);
        b.transact_mut()
            .apply_update(Update::decode_v1(&shapes[1].1[0]).unwrap())
            .unwrap();
        let xb = b.get_or_insert_text("x");
        xb.insert(&mut b.transact_mut(), 1, "ZZZ");
        xb.remove_range(&mut b.transact_mut(), 0, 3);
        shapes.push((
            "two clients",
            vec![b
                .transact()
                .encode_state_as_update_v1(&StateVector::default())],
        ));

        // client 3 writes "x", "y", "z" in three updates; leading gap gets only the last
        // two, middle gap the first and last.
        let c = doc(3);
        let mut updates = Vec::new();
        for root in ["x", "y", "z"] {
            let sv = c.transact().state_vector();
            let t = c.get_or_insert_text(root);
            t.insert(&mut c.transact_mut(), 0, "hello");
            t.remove_range(&mut c.transact_mut(), 1, 2);
            updates.push(c.transact().encode_diff_v1(&sv));
        }
        shapes.push(("leading gap", vec![updates[1].clone(), updates[2].clone()]));
        shapes.push(("middle gap", vec![updates[0].clone(), updates[2].clone()]));

        // surrogate pairs: clocks count UTF-16 units, so odd clocks land inside an emoji
        let e = doc(4);
        let x = e.get_or_insert_text("x");
        x.insert(&mut e.transact_mut(), 0, "a\u{1F600}\u{1F600}b\u{1F600}c");
        x.remove_range(&mut e.transact_mut(), 5, 4);
        x.insert(&mut e.transact_mut(), 1, "\u{1F600}");
        shapes.push((
            "emoji",
            vec![e
                .transact()
                .encode_state_as_update_v1(&StateVector::default())],
        ));

        // a peer with gc enabled sends GC blocks for deleted content
        let g = Doc::with_options(Options {
            client_id: ClientID::new(5),
            skip_gc: false,
            ..Options::default()
        });
        let x = g.get_or_insert_text("x");
        x.insert(&mut g.transact_mut(), 0, "abcdef");
        x.remove_range(&mut g.transact_mut(), 1, 3);
        let y = g.get_or_insert_array("y");
        y.insert_range(&mut g.transact_mut(), 0, [1, 2, 3, 4]);
        y.remove_range(&mut g.transact_mut(), 0, 2);
        shapes.push((
            "gc blocks",
            vec![g
                .transact()
                .encode_state_as_update_v1(&StateVector::default())],
        ));

        // formatting, embeds, nested types
        let r = doc(6);
        let x = r.get_or_insert_text("x");
        x.insert(&mut r.transact_mut(), 0, "hello world");
        x.format(
            &mut r.transact_mut(),
            2,
            5,
            yrs::types::Attrs::from([("bold".into(), true.into())]),
        );
        x.insert_embed(&mut r.transact_mut(), 3, yrs::Any::from(1));
        x.remove_range(&mut r.transact_mut(), 4, 3);
        let z = r.get_or_insert_map("z");
        z.insert(&mut r.transact_mut(), "k", yrs::TextPrelim::new("nested"));
        z.insert(&mut r.transact_mut(), "k", "overwritten");
        shapes.push((
            "rich",
            vec![r
                .transact()
                .encode_state_as_update_v1(&StateVector::default())],
        ));
        shapes
    }

    fn build(updates: &[Vec<u8>]) -> Doc {
        let d = doc(100);
        for u in updates {
            d.transact_mut()
                .apply_update(Update::decode_v1(u).unwrap())
                .unwrap();
        }
        d
    }

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }
        fn pick<T: Copy>(&mut self, xs: &[T]) -> T {
            xs[(self.next() % xs.len() as u64) as usize]
        }
    }

    fn adversarial(rng: &mut Rng) -> Snapshot {
        const CLIENTS: [u64; 9] = [1, 2, 3, 4, 5, 6, 100, 7, MAX_CLIENT];
        const CLOCKS: [u32; 16] = [
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            13,
            15,
            u32::MAX - 1,
            u32::MAX,
        ];
        let mut sv = StateVector::default();
        for _ in 0..rng.next() % 4 {
            sv.set_max(ClientID::new(rng.pick(&CLIENTS)), rng.pick(&CLOCKS));
        }
        let mut ds = IdSet::new();
        for _ in 0..rng.next() % 4 {
            let start = rng.pick(&CLOCKS);
            let len = rng.pick(&[1, 2, 3, 7, u32::MAX]).min(u32::MAX - start);
            if len > 0 {
                ds.insert(ID::new(ClientID::new(rng.pick(&CLIENTS)), start), len);
            }
        }
        // go through the codec, as an untrusted snapshot does
        read_snapshot(&write_snapshot(&Snapshot::new(sv, ds), false), false).unwrap()
    }

    thread_local! {
        static PANIC_AT: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
    }

    fn panic_message(e: Box<dyn std::any::Any + Send>) -> String {
        let msg = e
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string()))
            .unwrap_or_default();
        format!("{msg} at {}", PANIC_AT.with(|p| p.borrow().clone()))
    }

    #[test]
    fn adversarial_snapshots_never_panic() {
        use crate::text::diff_between_snapshots;
        use std::panic::{catch_unwind, AssertUnwindSafe};

        std::panic::set_hook(Box::new(|info| {
            let at = info.location().map(|l| l.to_string()).unwrap_or_default();
            PANIC_AT.with(|p| *p.borrow_mut() = at);
        }));
        let mut rng = Rng(0x9E37_79B9_7F4A_7C15);
        let mut failures = std::collections::BTreeMap::<String, String>::new();
        for (name, updates) in shapes() {
            for _ in 0..1000 {
                let hi = adversarial(&mut rng);
                let lo = adversarial(&mut rng);
                let case = format!("{name}: hi={hi:?} lo={lo:?}");
                let mut record = |what: &str, r: Result<(), Box<dyn std::any::Any + Send>>| {
                    if let Err(e) = r {
                        failures
                            .entry(format!("{what}: {}", panic_message(e)))
                            .or_insert_with(|| case.clone());
                    }
                };

                record(
                    "codec v2",
                    catch_unwind(|| {
                        let bytes = write_snapshot(&hi, true);
                        assert_eq!(read_snapshot(&bytes, true).unwrap(), hi);
                    }),
                );

                let d = build(&updates);
                record(
                    "encode_state",
                    catch_unwind(AssertUnwindSafe(|| {
                        let mut v1 = EncoderV1::new();
                        encode_state_from_snapshot(&mut d.transact_mut(), hi.clone(), &mut v1)
                            .unwrap();
                        let mut v2 = EncoderV2::new();
                        encode_state_from_snapshot(&mut d.transact_mut(), hi.clone(), &mut v2)
                            .unwrap();
                        // the update must be valid: create_doc applies it to a fresh doc
                        let u = Update::decode_v2(&v2.to_vec()).unwrap();
                        Doc::new().transact_mut().apply_update(u).unwrap();
                        let u = Update::decode_v1(&v1.to_vec()).unwrap();
                        Doc::new().transact_mut().apply_update(u).unwrap();
                    })),
                );

                for (h, l) in [
                    (Some(hi.clone()), Some(lo.clone())),
                    (Some(hi.clone()), None),
                    (None, Some(lo.clone())),
                ] {
                    let d = build(&updates);
                    let texts: Vec<_> = ["x", "y", "z"]
                        .iter()
                        .map(|r| d.get_or_insert_text(*r))
                        .collect();
                    record(
                        "diff_between_snapshots",
                        catch_unwind(AssertUnwindSafe(|| {
                            let mut txn = d.transact_mut();
                            for t in &texts {
                                diff_between_snapshots(
                                    &mut txn,
                                    t,
                                    h.clone().map(SnapshotRef::new),
                                    l.clone().map(SnapshotRef::new),
                                )
                                .unwrap();
                            }
                        })),
                    );
                    record(
                        "after diff",
                        catch_unwind(AssertUnwindSafe(|| {
                            // the doc must stay usable after the diff transaction commits
                            let s = d
                                .transact()
                                .encode_state_as_update_v1(&StateVector::default());
                            build(&[s]);
                        })),
                    );
                }
            }
        }
        for (what, case) in &failures {
            eprintln!("PANIC {what}\n    first case: {case}");
        }
        assert!(failures.is_empty(), "{} distinct panics", failures.len());
    }
}
