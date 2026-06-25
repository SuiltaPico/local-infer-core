use ort::session::builder::SessionBuilder;
use oar_ocr::core::config::{OrtExecutionProvider, OrtSessionConfig};

use super::RuntimeConfig;
use crate::error::{InferError, Result};

pub fn ep_available(name: &str) -> bool {
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
    mut builder: SessionBuilder,
    component: &str,
    config: &RuntimeConfig,
) -> Result<SessionBuilder> {
    let eps = config.resolved_eps();
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
