//! C ABI for embedding `infer-core` as a dynamic library (`infer_core.dll`).

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;

use image::DynamicImage;
use infer_core::{Registry, RuntimeConfig};

const OK: c_int = 0;
const ERR: c_int = -1;

struct RegistryHandle {
    registry: Registry,
}

fn set_error(out_error: *mut *mut c_char, message: impl Into<String>) {
    if !out_error.is_null() {
        unsafe {
            *out_error = string_to_raw(message);
        }
    }
}

fn clear_error(out_error: *mut *mut c_char) {
    if !out_error.is_null() {
        unsafe {
            *out_error = ptr::null_mut();
        }
    }
}

fn string_to_raw(message: impl Into<String>) -> *mut c_char {
    CString::new(message.into())
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

fn read_cstr(c: *const c_char, label: &str) -> Result<&'static str, String> {
    if c.is_null() {
        return Err(format!("null {label}"));
    }
    unsafe { CStr::from_ptr(c) }
        .to_str()
        .map_err(|e| format!("invalid UTF-8 {label}: {e}"))
}

fn read_bytes(data: *const u8, len: usize) -> Result<&'static [u8], String> {
    if data.is_null() || len == 0 {
        return Err("empty image buffer".into());
    }
    Ok(unsafe { std::slice::from_raw_parts(data, len) })
}

fn run<F>(out_error: *mut *mut c_char, f: F) -> c_int
where
    F: FnOnce() -> Result<(), String>,
{
    match catch_unwind(AssertUnwindSafe(|| f())) {
        Ok(Ok(())) => {
            clear_error(out_error);
            OK
        }
        Ok(Err(message)) => {
            set_error(out_error, message);
            ERR
        }
        Err(_) => {
            set_error(out_error, "internal panic");
            ERR
        }
    }
}

fn map_infer_error(err: infer_core::InferError) -> String {
    err.to_string()
}

fn load_image_bytes(bytes: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(bytes).map_err(|e| e.to_string())
}

fn registry_handle(handle: *mut c_void) -> Result<&'static mut RegistryHandle, String> {
    unsafe {
        (handle as *mut RegistryHandle)
            .as_mut()
            .ok_or_else(|| "null registry handle".to_string())
    }
}

/// Library version string (static, do not free).
#[no_mangle]
pub extern "C" fn infer_core_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

/// Free a string previously returned by this library.
#[no_mangle]
pub unsafe extern "C" fn infer_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Open a manifest-driven registry under `models_dir`.
///
/// `runtime_config_json` may be null or empty for defaults.
#[no_mangle]
pub extern "C" fn infer_registry_create(
    models_dir: *const c_char,
    runtime_config_json: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let models_dir = read_cstr(models_dir, "models_dir")?;
        let runtime_config = if runtime_config_json.is_null() {
            RuntimeConfig::from_env_or_default()
        } else {
            let json = read_cstr(runtime_config_json, "runtime_config_json")?;
            if json.is_empty() {
                RuntimeConfig::from_env_or_default()
            } else {
                RuntimeConfig::from_json(json).map_err(map_infer_error)?
            }
        };
        Registry::open(Path::new(models_dir), runtime_config)
            .map(|registry| {
                Box::into_raw(Box::new(RegistryHandle { registry })) as *mut c_void
            })
            .map_err(map_infer_error)
    })) {
        Ok(Ok(ptr)) => {
            clear_error(out_error);
            ptr
        }
        Ok(Err(message)) => {
            set_error(out_error, message);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(out_error, "internal panic");
            ptr::null_mut()
        }
    }
}

/// Destroy a handle from [`infer_registry_create`].
#[no_mangle]
pub unsafe extern "C" fn infer_registry_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle as *mut RegistryHandle));
    }
}

/// OCR plain text from image bytes using `pack_id`.
#[no_mangle]
pub extern "C" fn infer_ocr_plain_text(
    handle: *mut c_void,
    pack_id: *const c_char,
    data: *const u8,
    len: usize,
    out_text: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let registry = registry_handle(handle)?;
        let pack_id = read_cstr(pack_id, "pack_id")?;
        let bytes = read_bytes(data, len)?;
        let img = load_image_bytes(bytes)?;
        let engine = registry
            .registry
            .load_ocr(pack_id)
            .map_err(map_infer_error)?;
        let text = engine.plain_text(&img).map_err(map_infer_error)?;
        if !out_text.is_null() {
            unsafe {
                *out_text = string_to_raw(text);
            }
        }
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn version_is_non_null() {
        let ptr = infer_core_version();
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap();
        assert!(!s.is_empty());
    }

    #[test]
    fn string_free_roundtrip() {
        let raw = string_to_raw("hello");
        assert!(!raw.is_null());
        unsafe { infer_string_free(raw) };
    }

    #[test]
    fn registry_rejects_missing_dir() {
        let dir = CString::new("/nonexistent/models/path").unwrap();
        let mut err: *mut c_char = ptr::null_mut();
        let handle = infer_registry_create(dir.as_ptr(), ptr::null(), &mut err);
        assert!(handle.is_null());
        assert!(!err.is_null());
        unsafe { infer_string_free(err) };
    }
}
