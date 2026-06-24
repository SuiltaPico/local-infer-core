use std::path::Path;

use image::RgbImage;
use ort::session::Session;
use ort::value::Tensor;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::runtime::{self, RuntimeConfig};

pub mod preprocess;

pub const INPUT_SIZE: u32 = 256;
pub const EMBED_DIM: usize = 512;

pub struct EmbedEngine {
    session: Session,
    input_name: String,
    output_name: String,
}

impl EmbedEngine {
    pub fn from_manifest(
        pack_dir: &Path,
        manifest: &Manifest,
        runtime_config: &RuntimeConfig,
    ) -> Result<Self> {
        let vision = manifest.file_path(pack_dir, "vision")?;
        Self::load(&vision, runtime_config)
    }

    pub fn load(model_path: &Path, runtime_config: &RuntimeConfig) -> Result<Self> {
        if !model_path.is_file() {
            return Err(InferError::Embed(format!(
                "vision model not found: {}",
                model_path.display()
            )));
        }

        let mut builder = Session::builder().map_err(|e| InferError::Embed(e.to_string()))?;
        builder = runtime::apply_session_builder(builder, "embed", runtime_config)?;
        let session = builder
            .commit_from_file(model_path)
            .map_err(|e| InferError::Embed(e.to_string()))?;

        let input_name = session
            .inputs()
            .first()
            .ok_or_else(|| InferError::Embed("ONNX model has no inputs".into()))?
            .name()
            .to_string();
        let output_name = session
            .outputs()
            .first()
            .ok_or_else(|| InferError::Embed("ONNX model has no outputs".into()))?
            .name()
            .to_string();

        Ok(Self {
            session,
            input_name,
            output_name,
        })
    }

    pub fn embed_rgb256(&mut self, rgb: &RgbImage) -> Result<Vec<f32>> {
        let tensor = rgb256_to_nchw(rgb);
        self.embed_nchw(&tensor)
    }

    pub fn embed_nchw(&mut self, nchw: &[f32]) -> Result<Vec<f32>> {
        let expected = 3 * INPUT_SIZE as usize * INPUT_SIZE as usize;
        if nchw.len() != expected {
            return Err(InferError::Embed(format!(
                "expected {expected} floats for NCHW input, got {}",
                nchw.len()
            )));
        }

        let input = Tensor::from_array((
            [1i64, 3, INPUT_SIZE as i64, INPUT_SIZE as i64],
            nchw.to_vec(),
        ))
        .map_err(|e| InferError::Embed(e.to_string()))?;

        let outputs = self
            .session
            .run(ort::inputs![self.input_name.as_str() => input])
            .map_err(|e| InferError::Embed(e.to_string()))?;

        let (_shape, data) = outputs[self.output_name.as_str()]
            .try_extract_tensor::<f32>()
            .map_err(|e| InferError::Embed(e.to_string()))?;

        finalize_embedding(data.to_vec())
    }
}

/// Convert RGB 256×256 to NCHW float tensor in [0, 1].
pub fn rgb256_to_nchw(rgb: &RgbImage) -> Vec<f32> {
    debug_assert_eq!(rgb.dimensions(), (INPUT_SIZE, INPUT_SIZE));
    let mut out = vec![0.0f32; 3 * INPUT_SIZE as usize * INPUT_SIZE as usize];
    let plane = (INPUT_SIZE * INPUT_SIZE) as usize;
    for y in 0..INPUT_SIZE {
        for x in 0..INPUT_SIZE {
            let pixel = rgb.get_pixel(x, y);
            let idx = (y * INPUT_SIZE + x) as usize;
            out[idx] = pixel[0] as f32 / 255.0;
            out[plane + idx] = pixel[1] as f32 / 255.0;
            out[2 * plane + idx] = pixel[2] as f32 / 255.0;
        }
    }
    out
}

pub fn l2_normalize(v: &mut [f32]) -> f32 {
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > f32::EPSILON {
        for x in v {
            *x /= norm;
        }
    }
    norm
}

pub fn finalize_embedding(mut embedding: Vec<f32>) -> Result<Vec<f32>> {
    if embedding.len() > EMBED_DIM {
        embedding.truncate(EMBED_DIM);
    }
    if embedding.len() < EMBED_DIM {
        return Err(InferError::Embed(format!(
            "embedding dim {} < expected {EMBED_DIM}",
            embedding.len()
        )));
    }
    l2_normalize(&mut embedding);
    Ok(embedding)
}

pub fn cosine(a: &[f32], b: &[f32]) -> f64 {
    debug_assert_eq!(a.len(), b.len());
    a.iter()
        .zip(b.iter())
        .map(|(x, y)| (*x as f64) * (*y as f64))
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    #[test]
    fn rgb256_tensor_range() {
        let rgb = RgbImage::from_pixel(INPUT_SIZE, INPUT_SIZE, Rgb([128, 64, 32]));
        let tensor = rgb256_to_nchw(&rgb);
        assert!((tensor[0] - 128.0 / 255.0).abs() < 1e-6);
        assert_eq!(tensor.len(), 3 * INPUT_SIZE as usize * INPUT_SIZE as usize);
    }
}
