use ort::session::builder::SessionBuilder;
use oar_ocr::core::config::{OrtExecutionProvider, OrtSessionConfig};

use crate::error::{InferError, Result};

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct RuntimeConfig {
    #[serde(default)]
    pub onnx: Option<OnnxConfig>,
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

    pub fn from_env_or_default() -> Self {
        if let Ok(text) = std::env::var("LOCAL_INFER_RUNTIME_CONFIG") {
            if let Ok(cfg) = Self::from_json(&text) {
                return cfg;
            }
        }
        Self::default()
    }

    pub fn onnx_config(&self) -> OnnxConfig {
        self.onnx.clone().unwrap_or_default()
    }

    pub fn resolved_eps(&self) -> Vec<String> {
        let onnx = self.onnx_config();
        if !onnx.execution_providers.is_empty()
            && !onnx.execution_providers.iter().any(|ep| ep == "auto")
        {
            return maybe_append_cpu(onnx.execution_providers, onnx.append_cpu_fallback);
        }

        if let Ok(raw) = std::env::var("LOCAL_INFER_ORT_EP") {
            let eps: Vec<String> = raw
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
            if !eps.is_empty() {
                return maybe_append_cpu(eps, onnx.append_cpu_fallback);
            }
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
    #[cfg(target_os = "windows")]
    {
        if ep_available("directml") {
            return vec!["directml".into()];
        }
    }
    #[cfg(target_os = "macos")]
    {
        if ep_available("coreml") {
            return vec!["coreml".into()];
        }
    }
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    {
        if ep_available("cuda") {
            return vec!["cuda".into()];
        }
    }
    vec![]
}

fn resolved_eps_has_gpu(eps: &[String]) -> bool {
    eps.iter().any(|ep| matches!(ep.as_str(), "directml" | "coreml" | "cuda"))
}

fn ep_available(name: &str) -> bool {
    match name {
        "directml" => {
            #[cfg(target_os = "windows")]
            {
                use ort::ep::{DirectML, ExecutionProvider};
                DirectML::default().is_available().unwrap_or(false)
            }
            #[cfg(not(target_os = "windows"))]
            {
                false
            }
        }
        "coreml" => {
            #[cfg(target_os = "macos")]
            {
                use ort::ep::{CoreML, ExecutionProvider};
                CoreML::default().is_available().unwrap_or(false)
            }
            #[cfg(not(target_os = "macos"))]
            {
                false
            }
        }
        "cuda" => {
            #[cfg(feature = "ort-cuda")]
            {
                use ort::ep::{CUDA, ExecutionProvider};
                CUDA::default().is_available().unwrap_or(false)
            }
            #[cfg(not(feature = "ort-cuda"))]
            {
                false
            }
        }
        "cpu" => true,
        _ => false,
    }
}

/// Apply resolved EP chain to a direct `ort` session builder.
pub fn apply_session_builder(
    builder: SessionBuilder,
    component: &str,
    config: &RuntimeConfig,
) -> Result<SessionBuilder> {
    let eps = config.resolved_eps();
    let mut builder = builder;
    let mut attached = false;

    for ep in &eps {
        match ep.as_str() {
            "cpu" => continue,
            "directml" => {
                #[cfg(target_os = "windows")]
                {
                    use ort::ep::{DirectML, ExecutionProvider};
                    if DirectML::default().is_available().unwrap_or(false) {
                        eprintln!("{component}: using DirectML (GPU)");
                        builder = builder
                            .with_execution_providers([DirectML::default().build()])
                            .map_err(|e| InferError::Runtime(e.to_string()))?;
                        attached = true;
                        break;
                    }
                    eprintln!("{component}: DirectML unavailable, skipping");
                }
            }
            "coreml" => {
                #[cfg(all(target_os = "macos", feature = "ort-coreml"))]
                {
                    use ort::ep::{CoreML, ExecutionProvider};
                    if CoreML::default().is_available().unwrap_or(false) {
                        eprintln!("{component}: using CoreML (GPU)");
                        builder = builder
                            .with_execution_providers([CoreML::default().build()])
                            .map_err(|e| InferError::Runtime(e.to_string()))?;
                        attached = true;
                        break;
                    }
                    eprintln!("{component}: CoreML unavailable, skipping");
                }
            }
            "cuda" => {
                #[cfg(feature = "ort-cuda")]
                {
                    use ort::ep::{CUDA, ExecutionProvider};
                    if CUDA::default().is_available().unwrap_or(false) {
                        eprintln!("{component}: using CUDA (GPU)");
                        builder = builder
                            .with_execution_providers([CUDA::default().build()])
                            .map_err(|e| InferError::Runtime(e.to_string()))?;
                        attached = true;
                        break;
                    }
                    eprintln!("{component}: CUDA unavailable, skipping");
                }
            }
            other => eprintln!("{component}: unknown EP {other}, skipping"),
        }
    }

    if !attached {
        eprintln!("{component}: using CPU");
    }
    Ok(builder)
}

/// ONNX Runtime session config for `oar-ocr` pipelines.
pub fn oar_session_config(component: &str, config: &RuntimeConfig) -> Option<OrtSessionConfig> {
    let eps = config.resolved_eps();

    for ep in &eps {
        if ep == "directml" && ep_available("directml") {
            eprintln!("{component}: using DirectML (GPU)");
            return Some(
                OrtSessionConfig::new().with_execution_providers(vec![
                    OrtExecutionProvider::DirectML { device_id: None },
                    OrtExecutionProvider::CPU,
                ]),
            );
        }
    }

    eprintln!("{component}: using CPU");
    None
}

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
        };
        assert_eq!(cfg.resolved_eps(), vec!["cpu"]);
    }
}
