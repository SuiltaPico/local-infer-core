use std::path::Path;
use std::time::Instant;

use image::RgbImage;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::mnn_util::{self, MnnModel};
use crate::runtime::RuntimeConfig;

use super::{finalize_embedding, EmbedTimings, INPUT_SIZE};

pub struct EmbedEngine {
    model: MnnModel,
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
        let model = MnnModel::load(model_path, runtime_config, "embed")?;
        Ok(Self {
            model,
            runtime_config: runtime_config.clone(),
        })
    }

    pub fn session_backend_names(&self) -> Vec<String> {
        self.model.session_backend_names()
    }

    pub fn embed_rgb256(&mut self, rgb: &RgbImage) -> Result<Vec<f32>> {
        self.embed_rgb256_batch(std::slice::from_ref(rgb))?
            .into_iter()
            .next()
            .ok_or_else(|| InferError::Embed("empty embed batch".into()))
    }

    pub fn embed_rgb256_batch(&mut self, images: &[RgbImage]) -> Result<Vec<Vec<f32>>> {
        Ok(self.embed_rgb256_batch_timed(images)?.0)
    }

    pub fn embed_rgb256_batch_timed(
        &mut self,
        images: &[RgbImage],
    ) -> Result<(Vec<Vec<f32>>, EmbedTimings)> {
        if images.is_empty() {
            return Ok((Vec::new(), EmbedTimings::default()));
        }
        for rgb in images {
            if rgb.dimensions() != (INPUT_SIZE, INPUT_SIZE) {
                return Err(InferError::Embed(format!(
                    "expected {}×{} RGB image, got {}×{}",
                    INPUT_SIZE,
                    INPUT_SIZE,
                    rgb.width(),
                    rgb.height()
                )));
            }
        }

        let mut out = Vec::with_capacity(images.len());
        let mut timings = EmbedTimings::default();
        let batch_size = self.runtime_config.embed_batch();
        for chunk in images.chunks(batch_size) {
            let (partial, chunk_timings) =
                run_embed_batch(&mut self.model, chunk, batch_size)?;
            out.extend(partial);
            timings.merge(&chunk_timings);
        }
        timings.image_count = images.len() as u32;
        Ok((out, timings))
    }

    /// Run one padded batch at the configured embed batch size and persist MNN cache.
    pub fn warm_up_mnn(&mut self) -> Result<()> {
        let batch_size = self.runtime_config.embed_batch();
        let blank = blank_rgb256();
        let images: Vec<RgbImage> = (0..batch_size).map(|_| blank.clone()).collect();
        run_embed_batch(&mut self.model, &images, batch_size)?;
        self.model.persist_cache()
    }

    pub fn embed_nchw(&mut self, nchw: &[f32]) -> Result<Vec<f32>> {
        let expected = 3 * INPUT_SIZE as usize * INPUT_SIZE as usize;
        if nchw.len() != expected {
            return Err(InferError::Embed(format!(
                "expected {expected} floats for NCHW input, got {}",
                nchw.len()
            )));
        }

        let input_name = self.model.input_name.clone();
        let output_name = self.model.output_name.clone();
        let mut input = self
            .model
            .interpreter
            .input(&self.model.session, &input_name)
            .map_err(|e| mnn_util::map_err("embed", e))?;

        let mut host = input.create_host_tensor_from_device(false);
        host.host_mut().copy_from_slice(nchw);
        input
            .copy_from_host_tensor(&host)
            .map_err(|e| mnn_util::map_err("embed", e))?;

        self.model
            .interpreter
            .run_session(&self.model.session)
            .map_err(|e| mnn_util::map_err("embed", e))?;

        let raw = mnn_util::read_output_f32(
            &self.model.interpreter,
            &self.model.session,
            &output_name,
            "embed",
        )?;
        finalize_embedding(raw)
    }
}

fn blank_rgb256() -> RgbImage {
    image::RgbImage::from_pixel(INPUT_SIZE, INPUT_SIZE, image::Rgb([255, 255, 255]))
}

fn run_embed_batch(
    model: &mut MnnModel,
    images: &[RgbImage],
    fixed_batch_size: usize,
) -> Result<(Vec<Vec<f32>>, EmbedTimings)> {
    let real_count = images.len();
    if real_count == 0 || real_count > fixed_batch_size {
        return Err(InferError::Embed(format!(
            "embed batch size {real_count} out of range for fixed batch {fixed_batch_size}"
        )));
    }

    let mut timings = EmbedTimings {
        batch_runs: 1,
        image_count: real_count as u32,
        ..EmbedTimings::default()
    };

    let batch_size = fixed_batch_size as u16;
    let h = INPUT_SIZE as u16;
    let w = INPUT_SIZE as u16;
    let input_name = model.input_name.clone();
    let output_name = model.output_name.clone();

    let mut padded: Vec<RgbImage> = images.to_vec();
    if padded.len() < fixed_batch_size {
        let blank = blank_rgb256();
        padded.extend((0..fixed_batch_size - real_count).map(|_| blank.clone()));
    }

    let resize_start = Instant::now();
    let mut input =
        unsafe { model.interpreter.input_unresized::<f32>(&model.session, &input_name) }
            .map_err(|e| mnn_util::map_err("embed", e))?;
    model
        .interpreter
        .resize_tensor_by_nchw(&mut input, batch_size, 3, h, w);
    drop(input);
    model.interpreter.resize_session(&mut model.session);
    timings.resize_ms = ms_since(resize_start);

    let pack_start = Instant::now();
    let nchw = mnn_util::batch_rgb256_to_nchw(&padded, INPUT_SIZE);
    timings.pack_nchw_ms = ms_since(pack_start);

    let copy_start = Instant::now();
    let mut input = model
        .interpreter
        .input(&model.session, &input_name)
        .map_err(|e| mnn_util::map_err("embed", e))?;
    let mut host = input.create_host_tensor_from_device(false);
    host.host_mut().copy_from_slice(&nchw);
    input
        .copy_from_host_tensor(&host)
        .map_err(|e| mnn_util::map_err("embed", e))?;
    drop(input);
    timings.copy_input_ms = ms_since(copy_start);

    let run_start = Instant::now();
    model
        .interpreter
        .run_session(&model.session)
        .map_err(|e| mnn_util::map_err("embed", e))?;
    timings.run_session_ms = ms_since(run_start);

    let read_start = Instant::now();
    let raw = mnn_util::read_output_f32(
        &model.interpreter,
        &model.session,
        &output_name,
        "embed",
    )?;
    let output = model
        .interpreter
        .output(&model.session, &output_name)
        .map_err(|e| mnn_util::map_err("embed", e))?;
    let embed_dim = embed_output_dim(&output, raw.len(), fixed_batch_size)?;
    timings.read_output_ms = ms_since(read_start);

    let finalize_start = Instant::now();
    let mut results = Vec::with_capacity(real_count);
    for i in 0..real_count {
        let start = i * embed_dim;
        let end = start + embed_dim;
        results.push(finalize_embedding(raw[start..end].to_vec())?);
    }
    timings.finalize_ms = ms_since(finalize_start);

    Ok((results, timings))
}

fn embed_output_dim(
    output: &mnn::Tensor<mnn::Ref<'_, mnn::Device<f32>>>,
    raw_len: usize,
    batch: usize,
) -> Result<usize> {
    let shape = output.shape();
    let dims: Vec<i32> = shape.as_ref().to_vec();
    if let [_, dim] | [_, _, dim] = dims.as_slice() {
        return Ok(*dim as usize);
    }
    if batch == 0 {
        return Err(InferError::Embed("empty embed batch".into()));
    }
    if raw_len % batch != 0 {
        return Err(InferError::Embed(format!(
            "embed output size {raw_len} not divisible by batch {batch}"
        )));
    }
    Ok(raw_len / batch)
}

fn ms_since(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    #[test]
    fn batch_rgb256_tensor_size() {
        let rgb = image::RgbImage::from_pixel(INPUT_SIZE, INPUT_SIZE, Rgb([128, 64, 32]));
        let nchw = mnn_util::batch_rgb256_to_nchw(std::slice::from_ref(&rgb), INPUT_SIZE);
        assert_eq!(nchw.len(), 3 * INPUT_SIZE as usize * INPUT_SIZE as usize);
    }
}
