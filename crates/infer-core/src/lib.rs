#![cfg_attr(
    not(any(feature = "backend-ort", feature = "backend-mnn")),
    allow(unused, reason = "compile_error below")
)]

#[cfg(all(feature = "backend-ort", feature = "backend-mnn"))]
compile_error!("enable either backend-ort or backend-mnn, not both");

#[cfg(not(any(feature = "backend-ort", feature = "backend-mnn")))]
compile_error!("infer-core requires either backend-ort or backend-mnn feature");

#[cfg(feature = "backend-mnn")]
mod mnn_util;

pub mod embed;
pub mod error;
pub mod icon_index;
pub mod manifest;
pub mod ocr;
pub mod registry;
pub mod runtime;

pub use embed::{cosine, l2_normalize, EmbedEngine, EMBED_DIM, INPUT_SIZE};
pub use error::{InferError, Result};
pub use icon_index::{EmbeddingIndex, IconIndex, IconMatch, IndexStorageFormat};
pub use manifest::{LicenseInfo, Manifest};
pub use ocr::{OcrBounds, OcrConfig, OcrDetectionConfig, OcrEngine, OcrTimings, OcrWord};
pub use registry::Registry;
pub use runtime::{MnnConfig, OnnxConfig, RuntimeConfig};
