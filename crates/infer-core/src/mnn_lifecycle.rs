//! Serializes MNN session / interpreter teardown to avoid cross-engine GPU runtime races.

use std::cell::Cell;
use std::sync::{Mutex, OnceLock};

static MNN_TEARDOWN: OnceLock<Mutex<()>> = OnceLock::new();

thread_local! {
    static IN_MNN_TEARDOWN: Cell<bool> = const { Cell::new(false) };
}

/// Run [f] while holding the global MNN teardown lock.
///
/// Reentrant on the same thread (e.g. `clear_engine_cache` dropping cached `MnnModel`s).
pub fn with_teardown_lock<F, R>(f: F) -> R
where
    F: FnOnce() -> R,
{
    if IN_MNN_TEARDOWN.with(|flag| flag.get()) {
        return f();
    }
    let _guard = MNN_TEARDOWN
        .get_or_init(|| Mutex::new(()))
        .lock()
        .expect("MNN teardown lock poisoned");
    IN_MNN_TEARDOWN.with(|flag| flag.set(true));
    let result = f();
    IN_MNN_TEARDOWN.with(|flag| flag.set(false));
    result
}
