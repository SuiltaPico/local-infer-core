use std::path::Path;
use std::time::Instant;

use image::RgbImage;
use ort::session::Session;
use ort::value::Tensor;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::runtime::{self, RuntimeConfig};

use super::{finalize_embedding, rgb256_to_nchw, EmbedTimings, INPUT_SIZE};

pub struct EmbedEngine {
    session: Session,
    input_name: String,
    output_name: String,
    runtime_config: RuntimeConfig,
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
            runtime_config: runtime_config.clone(),
        })
    }

    pub fn embed_rgb256(&mut self, rgb: &RgbImage) -> Result<Vec<f32>> {
        let tensor = rgb256_to_nchw(rgb);
        self.embed_nchw(&tensor)
    }

    pub fn embed_rgb256_batch(&mut self, images: &[RgbImage]) -> Result<Vec<Vec<f32>>> {
        Ok(self.embed_rgb256_batch_timed(images)?.0)
    }

    pub fn embed_rgb256_batch_timed(
        &mut self,
        images: &[RgbImage],
    ) -> Result<(Vec<Vec<f32>>, EmbedTimings)> {
        let batch_size = self.runtime_config.embed_batch().max(1);
        let mut out = Vec::with_capacity(images.len());
        let mut timings = EmbedTimings::default();
        for chunk in images.chunks(batch_size) {
            let run_start = Instant::now();
            for rgb in chunk {
                out.push(self.embed_rgb256(rgb)?);
            }
            timings.run_session_ms += ms_since(run_start);
            timings.batch_runs += 1;
        }
        timings.image_count = images.len() as u32;
        Ok((out, timings))
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

fn ms_since(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}
