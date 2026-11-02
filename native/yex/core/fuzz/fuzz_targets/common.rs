/// libfuzzer-sys installs a panic hook that aborts on every panic, including the ones
/// `wire::guard` catches on purpose. Replace it with a silent one: a panic that escapes
/// `wire` still reaches libfuzzer-sys's own `catch_unwind` around the target, which
/// aborts and records the input.
pub fn quiet_caught_panics() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        std::panic::set_hook(Box::new(|i| {
            if std::env::var_os("FUZZ_SHOW_PANICS").is_some() {
                eprintln!("{i}")
            }
        }))
    });
}
