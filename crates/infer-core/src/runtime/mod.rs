#[cfg(feature = "backend-ort")]
mod ort;
#[cfg(feature = "backend-mnn")]
pub mod mnn;
mod capabilities;

use crate::error::Result;

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct RuntimeConfig {
    #[serde(default)]
    pub onnx: Option<OnnxConfig>,
    #[serde(default)]
    pub mnn: Option<MnnConfig>,
    #[serde(default)]
    pub batch: BatchConfig,
}

/// Batch sizes for OCR rec and icon/embed inference (clamped to 1–32 at use site).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BatchConfig {
    #[serde(default = "default_ocr_rec_batch")]
    pub ocr_rec: u32,
    #[serde(default = "default_embed_batch")]
    pub embed: u32,
    #[serde(default)]
    pub ocr_rec_strategy: OcrRecStrategy,
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OcrRecStrategy {
    None,
    Bucketing,
    Unified,
}

impl Default for OcrRecStrategy {
    fn default() -> Self {
        Self::None
    }
}

impl Default for BatchConfig {
    fn default() -> Self {
        Self {
            ocr_rec: default_ocr_rec_batch(),
            embed: default_embed_batch(),
            ocr_rec_strategy: OcrRecStrategy::default(),
        }
    }
}

const BATCH_MIN: u32 = 1;
const BATCH_MAX: u32 = 32;

fn default_ocr_rec_batch() -> u32 {
    8
}

fn default_embed_batch() -> u32 {
    8
}

fn clamp_batch_size(v: u32) -> usize {
    v.clamp(BATCH_MIN, BATCH_MAX) as usize
}

impl BatchConfig {
    pub fn ocr_rec_batch(&self) -> usize {
        clamp_batch_size(self.ocr_rec)
    }

    pub fn embed_batch(&self) -> usize {
        clamp_batch_size(self.embed)
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MnnConfig {
    #[serde(default = "default_mnn_backend")]
    pub backend: String,
    #[serde(default)]
    pub num_thread: Option<u32>,
    #[serde(default = "default_mnn_precision")]
    pub precision: String,
}

fn default_mnn_backend() -> String {
    "cpu".into()
}

fn default_mnn_precision() -> String {
    "normal".into()
}

impl Default for MnnConfig {
    fn default() -> Self {
        Self {
            backend: default_mnn_backend(),
            num_thread: None,
            precision: default_mnn_precision(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OnnxConfig {
    #[serde(default)]
    pub execution_providers: Vec<String>,
    #[serde(default)]
    pub intra_threads: Option<u32>,
    #[serde(default)]
    pub inter_threads: Option<u32>,
    #[serde(default = "default_true")]
    pub append_cpu_fallback: bool,
    #[serde(default = "default_true")]
    pub gpu_single_session: bool,
}

fn default_true() -> bool {
    true
}

impl Default for OnnxConfig {
    fn default() -> Self {
        Self {
            execution_providers: vec!["auto".into()],
            intra_threads: None,
            inter_threads: None,
            append_cpu_fallback: true,
            gpu_single_session: true,
        }
    }
}

impl RuntimeConfig {
    pub fn from_json(text: &str) -> Result<Self> {
        Ok(serde_json::from_str(text)?)
    }

    pub fn onnx_config(&self) -> OnnxConfig {
        self.onnx.clone().unwrap_or_default()
    }

    pub fn mnn_config(&self) -> MnnConfig {
        self.mnn.clone().unwrap_or_default()
    }

    pub fn batch_config(&self) -> BatchConfig {
        self.batch.clone()
    }

    pub fn ocr_rec_batch(&self) -> usize {
        self.batch_config().ocr_rec_batch()
    }

    pub fn ocr_rec_strategy(&self) -> OcrRecStrategy {
        self.batch_config().ocr_rec_strategy
    }

    pub fn embed_batch(&self) -> usize {
        self.batch_config().embed_batch()
    }

    /// Configured MNN backend after resolving `"auto"` to a concrete preference.
    pub fn resolved_mnn_backend(&self) -> String {
        let mnn = self.mnn_config();
        let backend = mnn.backend.trim();
        if !backend.is_empty() && backend != "auto" {
            return backend.to_string();
        }
        for name in ["vulkan", "opencl", "metal", "cuda"] {
            if available_backends().iter().any(|b| b == name) {
                return name.to_string();
            }
        }
        "cpu".to_string()
    }

    pub fn resolved_eps(&self) -> Vec<String> {
        let onnx = self.onnx_config();
        if !onnx.execution_providers.is_empty()
            && !onnx.execution_providers.iter().any(|ep| ep == "auto")
        {
            return maybe_append_cpu(onnx.execution_providers, onnx.append_cpu_fallback);
        }

        maybe_append_cpu(auto_eps(), onnx.append_cpu_fallback)
    }

    pub fn prefer_gpu_single_session(&self) -> bool {
        self.onnx_config().gpu_single_session && resolved_eps_has_gpu(&self.resolved_eps())
    }
}

fn maybe_append_cpu(mut eps: Vec<String>, append: bool) -> Vec<String> {
    if append && !eps.iter().any(|ep| ep == "cpu") {
        eps.push("cpu".into());
    }
    eps
}

fn auto_eps() -> Vec<String> {
    #[cfg(all(feature = "backend-ort", target_os = "windows"))]
    {
        if ep_available("directml") {
            return vec!["directml".into()];
        }
    }
    #[cfg(all(feature = "backend-ort", target_os = "macos"))]
    {
        if ep_available("coreml") {
            return vec!["coreml".into()];
        }
    }
    #[cfg(all(
        feature = "backend-ort",
        any(target_os = "linux", target_os = "windows")
    ))]
    {
        if ep_available("cuda") {
            return vec!["cuda".into()];
        }
    }
    vec![]
}

fn resolved_eps_has_gpu(eps: &[String]) -> bool {
    eps.iter()
        .any(|ep| matches!(ep.as_str(), "directml" | "coreml" | "cuda"))
}

#[cfg(feature = "backend-ort")]
fn ep_available(name: &str) -> bool {
    match name {
        "cpu" => true,
        #[cfg(feature = "backend-ort")]
        other => ort::ep_available(other),
        #[cfg(not(feature = "backend-ort"))]
        _ => false,
    }
}

#[cfg(feature = "backend-ort")]
pub use ort::{apply_session_builder, oar_session_config};

pub use capabilities::{available_backends, backend_kind, forward_type_name};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_appends_cpu_by_default() {
        let cfg = RuntimeConfig::default();
        let eps = cfg.resolved_eps();
        assert!(eps.last().map(|s| s.as_str()) == Some("cpu"));
    }

    #[test]
    fn explicit_cpu_only() {
        let cfg = RuntimeConfig {
            onnx: Some(OnnxConfig {
                execution_providers: vec!["cpu".into()],
                append_cpu_fallback: false,
                ..Default::default()
            }),
            ..Default::default()
        };
        assert_eq!(cfg.resolved_eps(), vec!["cpu"]);
    }

    #[test]
    fn batch_sizes_clamp_to_valid_range() {
        let cfg = RuntimeConfig {
            batch: BatchConfig {
                ocr_rec: 0,
                embed: 64,
                ocr_rec_strategy: OcrRecStrategy::Bucketing,
            },
            ..Default::default()
        };
        assert_eq!(cfg.ocr_rec_batch(), 1);
        assert_eq!(cfg.embed_batch(), 32);
        assert_eq!(cfg.ocr_rec_strategy(), OcrRecStrategy::Bucketing);
    }

    #[test]
    fn ocr_rec_strategy_serializes_snake_case() {
        let cfg = RuntimeConfig {
            batch: BatchConfig {
                ocr_rec_strategy: OcrRecStrategy::Unified,
                ..Default::default()
            },
            ..Default::default()
        };
        let json = serde_json::to_string(&cfg).unwrap();
        assert!(json.contains("\"ocr_rec_strategy\":\"unified\""));
    }

    #[test]
    fn resolved_mnn_backend_prefers_vulkan_when_available() {
        if !cfg!(feature = "backend-mnn") {
            return;
        }
        let cfg = RuntimeConfig {
            mnn: Some(MnnConfig {
                backend: "auto".into(),
                ..Default::default()
            }),
            ..Default::default()
        };
        let resolved = cfg.resolved_mnn_backend();
        assert!(
            ["vulkan", "opencl", "cpu"].contains(&resolved.as_str()),
            "unexpected resolved backend: {resolved}"
        );
    }
}
