//! C ABI for embedding `infer-core` as a dynamic library (`infer_core.dll`).

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;
use std::time::Instant;

use image::{DynamicImage, RgbImage};
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

unsafe fn write_out_json(out_json: *mut *mut c_char, json: &str) -> Result<(), String> {
    if out_json.is_null() {
        return Ok(());
    }
    let ptr = string_to_raw(json);
    if ptr.is_null() {
        return Err(format!(
            "failed to allocate output JSON ({} bytes)",
            json.len()
        ));
    }
    *out_json = ptr;
    Ok(())
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

fn load_rgb_bytes(bytes: &[u8], width: u32, height: u32) -> Result<RgbImage, String> {
    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixels| pixels.checked_mul(3))
        .ok_or_else(|| "invalid rgb dimensions".to_string())?;
    if bytes.len() != expected {
        return Err(format!(
            "rgb buffer length mismatch: got {}, expected {expected}",
            bytes.len()
        ));
    }
    RgbImage::from_raw(width, height, bytes.to_vec())
        .ok_or_else(|| "failed to build RgbImage".to_string())
}

fn instant_ms(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
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
            "decode_ms": timings.decode_ms,
            "resize_ms": timings.resize_ms,
            "det_ms": timings.det_ms,
            "rec_ms": timings.rec_ms,
            "post_ms": timings.post_ms,
            "mnn_configured_backend": timings.mnn_configured_backend,
            "mnn_session_backends": timings.mnn_session_backends,
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
        let payload = runtime_status_payload(&RuntimeConfig::default());
        let json = serde_json::to_string(&payload).map_err(|e| e.to_string())?;
        unsafe { write_out_json(out_json, &json)? };
        Ok(())
    })
}

/// JSON runtime status for a given config:
/// `{ "backend", "available", "configured", "resolved_mnn_backend" }`.
#[no_mangle]
pub extern "C" fn infer_runtime_status_json(
    runtime_config_json: *const c_char,
    out_json: *mut *mut c_char,
) -> c_int {
    run(std::ptr::null_mut(), || {
        let runtime_config = runtime_config_from_json_ptr(runtime_config_json)?;
        let payload = runtime_status_payload(&runtime_config);
        let json = serde_json::to_string(&payload).map_err(|e| e.to_string())?;
        unsafe { write_out_json(out_json, &json)? };
        Ok(())
    })
}

fn runtime_status_payload(runtime_config: &RuntimeConfig) -> serde_json::Value {
    serde_json::json!({
        "backend": infer_core_lib::runtime::backend_kind(),
        "available": infer_core_lib::runtime::available_backends(),
        "configured": runtime_config,
        "resolved_mnn_backend": if infer_core_lib::runtime::backend_kind() == "mnn" {
            Some(runtime_config.resolved_mnn_backend())
        } else {
            None::<String>
        },
        "resolved_eps": if infer_core_lib::runtime::backend_kind() == "onnx" {
            Some(runtime_config.resolved_eps())
        } else {
            None::<Vec<String>>
        },
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
        infer_core_lib::with_teardown_lock(|| {
            infer_core_lib::ocr::clear_engine_cache();
        });
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
        unsafe { write_out_json(out_json, &json)? };
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
        unsafe { write_out_json(out_json, &json)? };
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
        let decode_start = Instant::now();
        let img = load_image_bytes(bytes)?;
        let decode_ms = instant_ms(decode_start);
        let (words, mut timings) = engine
            .engine
            .recognize_timed(&img)
            .map_err(map_infer_error)?;
        timings.decode_ms = decode_ms;
        let json = ocr_words_to_json(&words, &timings)?;
        unsafe { write_out_json(out_json, &json)? };
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn infer_ocr_recognize_rgb_timed(
    handle: *mut c_void,
    rgb: *const u8,
    len: usize,
    width: u32,
    height: u32,
    out_json: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    run(out_error, || {
        let engine = ocr_engine_handle(handle)?;
        let bytes = read_bytes(rgb, len)?;
        let rgb = load_rgb_bytes(bytes, width, height)?;
        let (words, timings) = engine
            .engine
            .recognize_rgb_timed(rgb)
            .map_err(map_infer_error)?;
        let json = ocr_words_to_json(&words, &timings)?;
        unsafe { write_out_json(out_json, &json)? };
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
        #[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
        infer_core_lib::with_teardown_lock(|| {
            infer_core_lib::ocr::clear_engine_cache();
            drop(Box::from_raw(handle as *mut EmbedEngineHandle));
        });
        #[cfg(not(all(feature = "backend-mnn", not(feature = "backend-ort"))))]
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
pub extern "C" fn infer_embed_rgb256_batch(
    handle: *mut c_void,
    rgb_batch: *const u8,
    rgb_len: usize,
    count: usize,
    out_count: *mut usize,
    out_dim: *mut usize,
    out_error: *mut *mut c_char,
) -> *mut f32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let engine = embed_engine_handle(handle)?;
        if count == 0 {
            return Ok(Vec::new());
        }
        let bytes = read_bytes(rgb_batch, rgb_len)?;
        let per_image = infer_core_lib::INPUT_SIZE as usize
            * infer_core_lib::INPUT_SIZE as usize
            * 3;
        let expected = per_image * count;
        if bytes.len() != expected {
            return Err(format!(
                "rgb256 batch must be {expected} bytes ({count} images), got {}",
                bytes.len()
            ));
        }

        let mut images = Vec::with_capacity(count);
        for i in 0..count {
            let start = i * per_image;
            let end = start + per_image;
            let rgb = image::RgbImage::from_raw(
                infer_core_lib::INPUT_SIZE,
                infer_core_lib::INPUT_SIZE,
                bytes[start..end].to_vec(),
            )
            .ok_or_else(|| format!("invalid rgb256 buffer at index {i}"))?;
            images.push(rgb);
        }

        let embeddings = engine
            .engine
            .embed_rgb256_batch(&images)
            .map_err(map_infer_error)?;
        Ok(embeddings)
    }));

    match result {
        Ok(Ok(embeddings)) => {
            clear_error(out_error);
            let dim = embeddings.first().map(|e| e.len()).unwrap_or(0);
            if !out_count.is_null() {
                unsafe {
                    *out_count = embeddings.len();
                }
            }
            if !out_dim.is_null() {
                unsafe {
                    *out_dim = dim;
                }
            }
            let flat: Vec<f32> = embeddings.into_iter().flatten().collect();
            let mut boxed = flat.into_boxed_slice();
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
        unsafe { write_out_json(out_json, &json)? };
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
        unsafe { write_out_json(out_json, &json)? };
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
    fn write_out_json_rejects_interior_null() {
        let mut out: *mut c_char = ptr::null_mut();
        let err = unsafe { write_out_json(&mut out, "before\u{0}after") };
        assert!(err.is_err());
        assert!(out.is_null());
    }

    #[test]
    fn write_out_json_success() {
        let mut out: *mut c_char = ptr::null_mut();
        unsafe { write_out_json(&mut out, r#"{"ok":true}"#) }.unwrap();
        assert!(!out.is_null());
        let text = unsafe { CStr::from_ptr(out) }.to_str().unwrap();
        assert_eq!(text, r#"{"ok":true}"#);
        unsafe { infer_string_free(out) };
    }

    #[test]
    fn runtime_status_json_returns_payload() {
        let config = CString::new(r#"{"mnn":{"backend":"auto"}}"#).unwrap();
        let mut json: *mut c_char = ptr::null_mut();
        let rc = infer_runtime_status_json(config.as_ptr(), &mut json);
        assert_eq!(rc, OK);
        assert!(!json.is_null());
        let text = unsafe { CStr::from_ptr(json) }.to_str().unwrap();
        assert!(text.contains("\"available\""));
        assert!(text.contains("\"configured\""));
        unsafe { infer_string_free(json) };
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
            mnn_configured_backend: Some("vulkan".into()),
            mnn_session_backends: vec!["vulkan".into()],
        };
        let json = ocr_words_to_json(&words, &timings).unwrap();
        assert!(json.contains("\"text\":\"hi\""));
        assert!(json.contains("\"init_ms\":1"));
        assert!(json.contains("\"mnn_session_backends\""));
    }
}
