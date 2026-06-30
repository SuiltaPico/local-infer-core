//! C ABI for embedding `infer-core` as a dynamic library (`infer_core.dll`).

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;

use image::DynamicImage;
use infer_core_lib::{EmbedEngine, IconIndex, OcrEngine, OcrTimings, OcrWord, Registry, RuntimeConfig};

const OK: c_int = 0;
const ERR: c_int = -1;

struct RegistryHandle {
    registry: Registry,
}

struct OcrEngineHandle {
    engine: OcrEngine,
}

struct EmbedEngineHandle {
    engine: EmbedEngine,
}

struct IconIndexHandle {
    index: IconIndex,
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
    unsafe { Ok(std::slice::from_raw_parts(data, len)) }
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

fn map_infer_error(err: infer_core_lib::InferError) -> String {
    err.to_string()
}

fn load_image_bytes(bytes: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(bytes).map_err(|e| e.to_string())
}

fn runtime_config_from_json_ptr(json: *const c_char) -> Result<RuntimeConfig, String> {
    if json.is_null() {
        return Ok(RuntimeConfig::default());
    }
    let text = read_cstr(json, "runtime_config_json")?;
    if text.is_empty() {
        Ok(RuntimeConfig::default())
    } else {
        RuntimeConfig::from_json(text).map_err(map_infer_error)
    }
}

fn registry_handle(handle: *mut c_void) -> Result<&'static mut RegistryHandle, String> {
    unsafe {
        (handle as *mut RegistryHandle)
            .as_mut()
            .ok_or_else(|| "null registry handle".to_string())
    }
}

fn ocr_engine_handle(handle: *mut c_void) -> Result<&'static mut OcrEngineHandle, String> {
    unsafe {
        (handle as *mut OcrEngineHandle)
            .as_mut()
            .ok_or_else(|| "null OCR engine handle".to_string())
    }
}

fn embed_engine_handle(handle: *mut c_void) -> Result<&'static mut EmbedEngineHandle, String> {
    unsafe {
        (handle as *mut EmbedEngineHandle)
            .as_mut()
            .ok_or_else(|| "null embed engine handle".to_string())
    }
}

fn icon_index_handle(handle: *mut c_void) -> Result<&'static mut IconIndexHandle, String> {
    unsafe {
        (handle as *mut IconIndexHandle)
            .as_mut()
            .ok_or_else(|| "null icon index handle".to_string())
    }
}

fn ocr_words_to_json(words: &[OcrWord], timings: &OcrTimings) -> Result<String, String> {
    let payload = serde_json::json!({
        "words": words.iter().map(|w| serde_json::json!({
            "text": w.text,
            "bounds": {
                "x": w.bounds.x,
                "y": w.bounds.y,
                "width": w.bounds.width,
                "height": w.bounds.height,
            },
            "confidence": w.confidence,
        })).collect::<Vec<_>>(),
        "timings": {
            "init_ms": timings.init_ms,
            "predict_ms": timings.predict_ms,
        },
    });
    serde_json::to_string(&payload).map_err(|e| e.to_string())
}

fn read_floats(data: *const f32, len: usize) -> Result<&'static [f32], String> {
    if data.is_null() || len == 0 {
        return Err("empty embedding buffer".into());
    }
    unsafe { Ok(std::slice::from_raw_parts(data, len)) }
}

/// Library version string (static, do not free).
#[no_mangle]
pub extern "C" fn infer_core_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

/// JSON object: `{ "backend": "onnx"|"mnn", "available": ["cpu", ...] }`.
#[no_mangle]
pub extern "C" fn infer_runtime_backends_json(out_json: *mut *mut c_char) -> c_int {
    run(std::ptr::null_mut(), || {
        let payload = serde_json::json!({
            "backend": infer_core_lib::runtime::backend_kind(),
            "available": infer_core_lib::runtime::available_backends(),
        });
        let json = serde_json::to_string(&payload).map_err(|e| e.to_string())?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
            }
        }
        Ok(())
    })
}

/// Free a string previously returned by this library.
#[no_mangle]
pub unsafe extern "C" fn infer_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Free a float buffer previously returned by this library.
#[no_mangle]
pub unsafe extern "C" fn infer_floats_free(data: *mut f32, len: usize) {
    if !data.is_null() && len > 0 {
        drop(Vec::from_raw_parts(data, len, len));
    }
}

/// Open a manifest-driven registry under `models_dir`.
#[no_mangle]
pub extern "C" fn infer_registry_create(
    models_dir: *const c_char,
    runtime_config_json: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let models_dir = read_cstr(models_dir, "models_dir")?;
        let runtime_config = runtime_config_from_json_ptr(runtime_config_json)?;
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
        #[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
        infer_core_lib::ocr::clear_engine_cache();
        drop(Box::from_raw(handle as *mut RegistryHandle));
    }
}

#[no_mangle]
pub extern "C" fn infer_registry_pack_ids_json(
    handle: *mut c_void,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let registry = registry_handle(handle)?;
        let mut ids: Vec<&str> = registry.registry.pack_ids().collect();
        ids.sort_unstable();
        let json = serde_json::to_string(&ids).map_err(|e| e.to_string())?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_registry_manifest_json(
    handle: *mut c_void,
    pack_id: *const c_char,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let registry = registry_handle(handle)?;
        let pack_id = read_cstr(pack_id, "pack_id")?;
        let manifest = registry.registry.manifest(pack_id).map_err(map_infer_error)?;
        let json = serde_json::to_string(manifest).map_err(|e| e.to_string())?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_ocr_engine_load(
    handle: *mut c_void,
    pack_id: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let registry = registry_handle(handle)?;
        let pack_id = read_cstr(pack_id, "pack_id")?;
        registry
            .registry
            .load_ocr(pack_id)
            .map(|engine| {
                Box::into_raw(Box::new(OcrEngineHandle { engine })) as *mut c_void
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

#[no_mangle]
pub unsafe extern "C" fn infer_ocr_engine_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle as *mut OcrEngineHandle));
    }
}

#[no_mangle]
pub extern "C" fn infer_ocr_engine_apply_config(
    handle: *mut c_void,
    min_confidence: f32,
    max_side: u32,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let engine = ocr_engine_handle(handle)?;
        engine
            .engine
            .apply_config_overrides(Some(min_confidence), Some(max_side));
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_ocr_recognize_timed(
    handle: *mut c_void,
    data: *const u8,
    len: usize,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let engine = ocr_engine_handle(handle)?;
        let bytes = read_bytes(data, len)?;
        let img = load_image_bytes(bytes)?;
        let (words, timings) = engine
            .engine
            .recognize_timed(&img)
            .map_err(map_infer_error)?;
        let json = ocr_words_to_json(&words, &timings)?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_embed_engine_load(
    handle: *mut c_void,
    pack_id: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let registry = registry_handle(handle)?;
        let pack_id = read_cstr(pack_id, "pack_id")?;
        registry
            .registry
            .load_embed(pack_id)
            .map(|engine| {
                Box::into_raw(Box::new(EmbedEngineHandle { engine })) as *mut c_void
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

#[no_mangle]
pub extern "C" fn infer_embed_engine_load_path(
    model_path: *const c_char,
    runtime_config_json: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let model_path = read_cstr(model_path, "model_path")?;
        let runtime_config = runtime_config_from_json_ptr(runtime_config_json)?;
        EmbedEngine::load(Path::new(model_path), &runtime_config)
            .map(|engine| {
                Box::into_raw(Box::new(EmbedEngineHandle { engine })) as *mut c_void
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

#[no_mangle]
pub unsafe extern "C" fn infer_embed_engine_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle as *mut EmbedEngineHandle));
    }
}

#[no_mangle]
pub extern "C" fn infer_embed_rgb256(
    handle: *mut c_void,
    rgb256: *const u8,
    rgb_len: usize,
    out_dim: *mut usize,
    out_error: *mut *mut c_char,
) -> *mut f32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let engine = embed_engine_handle(handle)?;
        let bytes = read_bytes(rgb256, rgb_len)?;
        let expected = infer_core_lib::INPUT_SIZE as usize * infer_core_lib::INPUT_SIZE as usize * 3;
        if bytes.len() != expected {
            return Err(format!(
                "rgb256 buffer must be {expected} bytes, got {}",
                bytes.len()
            ));
        }
        let rgb = image::RgbImage::from_raw(
            infer_core_lib::INPUT_SIZE,
            infer_core_lib::INPUT_SIZE,
            bytes.to_vec(),
        )
        .ok_or_else(|| "invalid rgb256 buffer".to_string())?;
        let embedding = engine.engine.embed_rgb256(&rgb).map_err(map_infer_error)?;
        Ok(embedding)
    }));

    match result {
        Ok(Ok(embedding)) => {
            clear_error(out_error);
            if !out_dim.is_null() {
                unsafe {
                    *out_dim = embedding.len();
                }
            }
            let mut boxed = embedding.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            std::mem::forget(boxed);
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

#[no_mangle]
pub extern "C" fn infer_icon_index_load(
    handle: *mut c_void,
    pack_id: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(|| {
        let registry = registry_handle(handle)?;
        let pack_id = read_cstr(pack_id, "pack_id")?;
        registry
            .registry
            .load_icon_index(pack_id)
            .map(|index| Box::into_raw(Box::new(IconIndexHandle { index })) as *mut c_void)
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

#[no_mangle]
pub unsafe extern "C" fn infer_icon_index_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle as *mut IconIndexHandle));
    }
}

#[no_mangle]
pub extern "C" fn infer_icon_index_match_embedding(
    handle: *mut c_void,
    embedding: *const f32,
    dim: usize,
    min_cosine: f32,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let index = icon_index_handle(handle)?;
        let query = read_floats(embedding, dim)?;
        let expected_dim = index.index.embedding_index().dim as usize;
        if query.len() != expected_dim {
            return Err(format!(
                "embedding dim mismatch: expected {expected_dim}, got {}",
                query.len()
            ));
        }
        let matched = index
            .index
            .match_embedding(query, min_cosine as f64)
            .map(|m| serde_json::json!({ "name": m.name, "score": m.score }));
        let json = serde_json::to_string(&matched).map_err(|e| e.to_string())?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_icon_index_search(
    handle: *mut c_void,
    embedding: *const f32,
    dim: usize,
    top_k: usize,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let index = icon_index_handle(handle)?;
        let query = read_floats(embedding, dim)?;
        let expected_dim = index.index.embedding_index().dim as usize;
        if query.len() != expected_dim {
            return Err(format!(
                "embedding dim mismatch: expected {expected_dim}, got {}",
                query.len()
            ));
        }
        let hits = index.index.search(query, top_k.max(1));
        let json_hits: Vec<serde_json::Value> = hits
            .into_iter()
            .map(|m| serde_json::json!({ "name": m.name, "score": m.score }))
            .collect();
        let json = serde_json::to_string(&json_hits).map_err(|e| e.to_string())?;
        if !out_json.is_null() {
            unsafe {
                *out_json = string_to_raw(json);
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
    fn runtime_backends_json_is_non_empty() {
        let mut json: *mut c_char = ptr::null_mut();
        let rc = infer_runtime_backends_json(&mut json);
        assert_eq!(rc, OK);
        assert!(!json.is_null());
        let text = unsafe { CStr::from_ptr(json) }.to_str().unwrap();
        assert!(text.contains("\"available\""));
        unsafe { infer_string_free(json) };
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

    #[test]
    fn ocr_bounds_json_roundtrip() {
        let words = vec![OcrWord {
            text: "hi".into(),
            bounds: infer_core_lib::OcrBounds::new(1, 2, 3, 4),
            confidence: 99.0,
        }];
        let timings = OcrTimings {
            init_ms: 1.0,
            predict_ms: 2.0,
        };
        let json = ocr_words_to_json(&words, &timings).unwrap();
        assert!(json.contains("\"text\":\"hi\""));
        assert!(json.contains("\"init_ms\":1"));
    }
}
