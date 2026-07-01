use std::mem::ManuallyDrop;
use std::path::Path;

use mnn::{Interpreter, Session, SessionMode};

use crate::error::{InferError, Result};
use crate::runtime::{self, RuntimeConfig};

pub fn map_err(component: &str, err: mnn::MNNError) -> InferError {
    InferError::Runtime(format!("{component}: {err}"))
}

pub fn first_io_name(
    interpreter: &Interpreter,
    session: &Session,
    inputs: bool,
) -> Result<String> {
    let list = if inputs {
        interpreter.inputs(session)
    } else {
        interpreter.outputs(session)
    };
    let info = list.get(0).ok_or_else(|| {
        InferError::Runtime(
            if inputs {
                "MNN model has no inputs"
            } else {
                "MNN model has no outputs"
            }
            .into(),
        )
    })?;
    Ok(info.name().to_string())
}

/// Loaded MNN model + session.
///
/// Session must be released before the interpreter is destroyed (`releaseSession` then
/// `Interpreter_destroy`). Rust drops struct fields in declaration order, so keep
/// `session` before `interpreter` and enforce teardown in [`Drop`].
pub struct MnnModel {
    pub session: ManuallyDrop<Session>,
    pub interpreter: ManuallyDrop<Interpreter>,
    pub input_name: String,
    pub output_name: String,
}

unsafe impl Send for MnnModel {}
unsafe impl Sync for MnnModel {}

impl Drop for MnnModel {
    fn drop(&mut self) {
        crate::mnn_lifecycle::with_teardown_lock(|| unsafe {
            ManuallyDrop::drop(&mut self.session);
            ManuallyDrop::drop(&mut self.interpreter);
        });
    }
}

impl MnnModel {
    /// MNN forward types actually used by this session.
    pub fn session_backend_names(&self) -> Vec<String> {
        self.interpreter
            .backends(&self.session)
            .unwrap_or_default()
            .into_iter()
            .map(|code| runtime::forward_type_name(code).to_string())
            .collect()
    }

    pub fn load(path: &Path, runtime_config: &RuntimeConfig, component: &str) -> Result<Self> {
        let mut interpreter =
            Interpreter::from_file(path).map_err(|e| map_err(component, e))?;
        interpreter.set_session_mode(SessionMode::MemoryCache);
        let cache_path = mnn_cache_path(path);
        let _ = interpreter.set_cache_file(&cache_path, 128);
        let mut session = interpreter
            .create_session(runtime::mnn::schedule_config(runtime_config))
            .map_err(|e| map_err(component, e))?;
        let _ = interpreter.update_cache_file(&mut session);
        let input_name = first_io_name(&interpreter, &session, true)?;
        let output_name = first_io_name(&interpreter, &session, false)?;
        Ok(Self {
            session: ManuallyDrop::new(session),
            interpreter: ManuallyDrop::new(interpreter),
            input_name,
            output_name,
        })
    }
}

/// Backend kernel cache path for an MNN model (`.mnn` → `.cache` beside the model).
fn mnn_cache_path(model_path: &Path) -> std::path::PathBuf {
    model_path.with_extension("cache")
}

/// RGB HWC → NCHW with ImageNet normalization (Paddle det).
pub fn rgb_to_nchw_imagenet(rgb: &image::RgbImage) -> Vec<f32> {
    let (w, h) = rgb.dimensions();
    let plane = (w * h) as usize;
    let mut out = vec![0.0f32; 3 * plane];
    let mean = [0.485f32, 0.456, 0.406];
    let std = [0.229f32, 0.224, 0.225];
    for y in 0..h {
        for x in 0..w {
            let idx = (y * w + x) as usize;
            let p = rgb.get_pixel(x, y);
            for c in 0..3 {
                let v = p[c] as f32 / 255.0;
                out[c * plane + idx] = (v - mean[c]) / std[c];
            }
        }
    }
    out
}

/// Stack N rec crops (same H, padded to `pad_w`) into `[N, 3, H, W]` NCHW.
pub fn batch_rgb_to_nchw_rec(
    crops: &[image::RgbImage],
    rec_height: u32,
    pad_w: u32,
) -> Vec<f32> {
    let batch = crops.len();
    let plane = (rec_height * pad_w) as usize;
    let mut out = vec![0.0f32; batch * 3 * plane];
    for (b, crop) in crops.iter().enumerate() {
        let (w, h) = crop.dimensions();
        debug_assert!(h == rec_height && w <= pad_w);
        let base = b * 3 * plane;
        for y in 0..h {
            for x in 0..w {
                let idx = (y * pad_w + x) as usize;
                let p = crop.get_pixel(x, y);
                for c in 0..3 {
                    out[base + c * plane + idx] = p[c] as f32 / 127.5 - 1.0;
                }
            }
        }
    }
    out
}

/// Stack N fixed-size RGB images into `[N, 3, H, W]` NCHW in [0, 1].
pub fn batch_rgb256_to_nchw(images: &[image::RgbImage], size: u32) -> Vec<f32> {
    let batch = images.len();
    let plane = (size * size) as usize;
    let mut out = vec![0.0f32; batch * 3 * plane];
    for (b, rgb) in images.iter().enumerate() {
        debug_assert_eq!(rgb.dimensions(), (size, size));
        let base = b * 3 * plane;
        for y in 0..size {
            for x in 0..size {
                let idx = (y * size + x) as usize;
                let p = rgb.get_pixel(x, y);
                out[base + idx] = p[0] as f32 / 255.0;
                out[base + plane + idx] = p[1] as f32 / 255.0;
                out[base + 2 * plane + idx] = p[2] as f32 / 255.0;
            }
        }
    }
    out
}

pub fn read_output_f32(
    interpreter: &Interpreter,
    session: &Session,
    output_name: &str,
    component: &str,
) -> Result<Vec<f32>> {
    let output = interpreter
        .output(session, output_name)
        .map_err(|e| map_err(component, e))?;
    output.wait(mnn::MapType::MAP_TENSOR_READ, true);
    let host = output.create_host_tensor_from_device(true);
    Ok(host.host().to_vec())
}
