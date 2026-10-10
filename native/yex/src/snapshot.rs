use yrs::branch::{Branch, BranchPtr};
use yrs::types::text::YChange;
use yrs::types::TypeRef;
use yrs::updates::encoder::Encoder as UpdatesEncoder;
use yrs::{IdSet, ReadTxn, Snapshot, StateVector, Text, TextRef, TransactionMut};

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
    snapshot: &Snapshot,
    encoder: &mut E,
) -> Result<(), yrs::error::Error> {
    let local = txn.state_vector();
    let state_map: StateVector = snapshot
        .state_map
        .iter()
        .filter(|(client, _)| local.get(client) > 0)
        .map(|(client, clock)| (*client, *clock))
        .collect();
    let detached = Branch::new(TypeRef::Text);
    let split = Snapshot::new(state_map.clone(), IdSet::default());
    TextRef::from(BranchPtr::from(&*detached)).diff_range(
        txn,
        Some(&split),
        None,
        YChange::identity,
    );
    let snapshot = Snapshot::new(state_map, snapshot.delete_set.clone());
    txn.encode_state_from_snapshot(&snapshot, encoder)
}

#[cfg(test)]
mod tests {
    use super::*;
    use yrs::updates::decoder::Decode;
    use yrs::updates::encoder::{EncoderV1, EncoderV2};
    use yrs::{ClientID, Doc, GetString, Options, Transact, Update};

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
        encode_state_from_snapshot(&mut a.transact_mut(), &s, &mut v1).unwrap();
        let mut v2 = EncoderV2::new();
        encode_state_from_snapshot(&mut a.transact_mut(), &s, &mut v2).unwrap();
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
        encode_state_from_snapshot(&mut b.transact_mut(), &snapshot, &mut v1).unwrap();
        let mut v2 = EncoderV2::new();
        encode_state_from_snapshot(&mut b.transact_mut(), &snapshot, &mut v2).unwrap();
        // client 1 is left out entirely: an empty update
        assert_eq!(v1.to_vec(), vec![0, 0]);
    }
}
