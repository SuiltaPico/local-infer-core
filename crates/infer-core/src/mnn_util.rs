use std::mem::ManuallyDrop;
use std::path::Path;

use mnn::{Interpreter, Session};

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
        unsafe {
            ManuallyDrop::drop(&mut self.session);
            ManuallyDrop::drop(&mut self.interpreter);
        }
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
        let session = interpreter
            .create_session(runtime::mnn::schedule_config(runtime_config))
            .map_err(|e| map_err(component, e))?;
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

/// RGB HWC → NCHW with `x = pixel/127.5 - 1` (Paddle rec).
pub fn rgb_to_nchw_rec(rgb: &image::RgbImage) -> Vec<f32> {
    let (w, h) = rgb.dimensions();
    let plane = (w * h) as usize;
    let mut out = vec![0.0f32; 3 * plane];
    for y in 0..h {
        for x in 0..w {
            let idx = (y * w + x) as usize;
            let p = rgb.get_pixel(x, y);
            for c in 0..3 {
                out[c * plane + idx] = p[c] as f32 / 127.5 - 1.0;
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
