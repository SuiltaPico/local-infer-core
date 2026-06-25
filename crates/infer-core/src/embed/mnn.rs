use std::path::Path;

use image::RgbImage;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::mnn_util::{self, MnnModel};
use crate::runtime::RuntimeConfig;

use super::{finalize_embedding, rgb256_to_nchw, INPUT_SIZE};

pub struct EmbedEngine {
    model: MnnModel,
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
        Ok(Self { model })
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
