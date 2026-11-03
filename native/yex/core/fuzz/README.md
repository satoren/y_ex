# yex-core fuzz targets

Fuzzes `yex_core::wire`, the only place the NIF decodes and applies bytes from outside.
A finding is a panic that escapes `wire` or an abort. In the NIF an escaped panic raises
in the Elixir caller, and an abort terminates the whole BEAM VM.

```sh
cd native/yex/core
CARGO_PROFILE_RELEASE_LTO=false ASAN_OPTIONS=allocator_may_return_null=1 \
  cargo +nightly fuzz run -O update_v1 -- -max_total_time=300 -malloc_limit_mb=65536
```

- `-O` builds like the released NIF (no overflow checks). Drop it to also catch arithmetic
  overflow, which release builds wrap silently.
- `CARGO_PROFILE_RELEASE_LTO=false` overrides `lto = true` from `native/yex/.cargo/config.toml`;
  LTO with sanitizer coverage fails to link on current nightlies.
- `allocator_may_return_null=1` and a high `-malloc_limit_mb` let yrs's `try_reserve` on
  huge declared lengths fail the way it does under the system allocator, instead of being
  reported as an out-of-memory finding.
- Set `FUZZ_SHOW_PANICS=1` when reproducing to print the panics `wire` catches.

Targets: `update_v1`, `update_v2` (decode, apply, commit), `small_values` (state vectors,
sticky indexes, snapshots, awareness, v2 message framing), `merge_and_diff`.
