# Exact text item resolution: paired contribution

This additive prototype adds `Yex.StickyIndex.resolve_text_items/2`. It requires
the companion Yrs changes adding scalar and cached batch `get_offsets_without_redone`;
these methods are not in the published Yrs 0.25.0 package. The native dependency
temporarily pins the public `boldflight/y-crdt` fork at immutable commit
`36e9df5b1f55657837161312c54a8296aaadb68a`. No package release is claimed.

The API resolves bounded item-ID runs against a supplied XML text in one read
transaction on a dirty CPU scheduler. It compares the actual containing branch,
including collapsed positions. Original deleted items remain collapsed after
undo/redo rather than acquiring ownership of recreated content. Unknown or
garbage-collected items remain unavailable. The application must still establish
root reachability, plain-text eligibility, document ownership and human intent.

Limits are 4,096 runs and 131,072 total UTF-16 units. Input count and clock
overflow checks happen before output allocation. Malformed lists fail normally
rather than panicking in a native iterator. Output preserves run and unit order.
An additional operational budget permits 262,144 unique linked items per call,
including formatting markers and deleted items. Exhaustion returns `:traversal_limit`
recoverably; it does not redefine the portable selection limits. Cached prefixes
exist only within one immutable Yrs transaction borrow and are never persisted.

## Local integration

The contribution worktrees start from Yex `v0.11.0` (`b9b06c9`) and Yrs
`v0.25.0` (`ef0b9bd`). The Yrs implementation stays inside its own library;
Yex uses only public Yrs methods and does not inspect private item structures.

For verification, use `RUSTLER_PRECOMPILATION_YEX_BUILD=true` for Mix commands.
Cargo.toml and Cargo.lock resolve the companion source directly from the public
Git commit, with no local path override. Restore a compatible released Yrs
dependency before a normal package release; the temporary fork pin is an explicit
integration dependency, not a claim that these APIs shipped in Yrs 0.25.0.

An isolated official Rust 1.98.1 toolchain was used without modifying shell or
system configuration. The official rustup installer SHA-256 was
`ec1b9233e7f72990ecd8e62063fa7f6c3dfc2bec8e97f88bff165f9100ac696a`.

## Evidence and limits

`test/sticky_index_text_items_test.exs` covers Yjs 13.6.32 fixtures with emoji,
multiple leaves, interior insertions, partial deletion and unavailable ancestors,
as well as wrong-type claims, transaction reuse, input bounds and undo/redo.
The fixture SHA-256 is
`a0efd05ceb97f6503be62f5b661f0abbdb2d97de22347d2f4734764da99b4e96`.

Run `MIX_ENV=test mix run benchmark/text_item_positions.exs` with the local build
enabled. On the development machine, a single plain leaf containing 131,072
selected units took 23 ms with the paired API, versus 10,562 ms for batching
public cursor resolution plus per-index identity roundtrips. The application-side
scalar validator took 12,112 ms on the same plain-text shape. These are local
measurements, not a latency guarantee for fragmented or adversarial documents.
The same selected length with 4,096 alternating formatting spans took 13,222 ms
before the prefix cache and 35 ms after it, with every resulting position checked.
Reproduce with `benchmark/fragmented_text_item_positions.exs`. These measurements
exclude document construction and formatting, and do not establish an adversarial
latency bound; the traversal budget provides a recoverable work limit.

The complete Yex suite passed 617 cases (63 doctests and 554 tests). The complete
Yrs library suite passed 340, ignored two, and failed its existing
`sync::awareness::test::awareness_summary` because independently produced timestamps
differed by one millisecond. That test and awareness implementation were unchanged.
The eleven focused moving/index tests, including cached/scalar equivalence,
budget exhaustion, invalid IDs, Unicode, deletion, branch and original-identity cases,
passed. No full green Yrs suite is claimed.

Yex already exposes `Doc.get_pending_update/1` and `Doc.get_pending_ds/1` via
public Yrs store accessors. Each returns `{:ok, nil}` when absent or `{:ok, binary}`
when present, reusing an active transaction. Existing tests cover pending insertions
and pending deletions becoming clear when their dependencies arrive. A caller can
require both absent before and after candidate application to exclude previously
pending structures from new-item admission; any error must also fail closed.
Document lifecycle, retention, authorization and production activation remain
application responsibilities.
