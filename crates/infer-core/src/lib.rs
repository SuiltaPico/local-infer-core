#![cfg_attr(
    not(any(
        feature = "backend-ort",
        feature = "backend-mnn",
        feature = "types-only"
    )),
    allow(unused, reason = "compile_error below")
)]

#[cfg(all(feature = "backend-ort", feature = "backend-mnn"))]
compile_error!("enable either backend-ort or backend-mnn, not both");

#[cfg(not(any(
    feature = "backend-ort",
    feature = "backend-mnn",
    feature = "types-only"
)))]
compile_error!("infer-core requires backend-ort, backend-mnn, or types-only feature");

#[cfg(all(feature = "backend-mnn", not(feature = "types-only")))]
mod mnn_lifecycle;
#[cfg(all(feature = "backend-mnn", not(feature = "types-only")))]
mod mnn_util;

#[cfg(all(feature = "backend-mnn", not(feature = "types-only")))]
pub use mnn_lifecycle::with_teardown_lock;

#[cfg(not(feature = "types-only"))]
pub mod embed;
pub mod error;
#[cfg(not(feature = "types-only"))]
pub mod icon_index;
pub mod manifest;
#[cfg(not(feature = "types-only"))]
pub mod ocr;
#[cfg(not(feature = "types-only"))]
pub mod registry;
pub mod runtime;

#[cfg(not(feature = "types-only"))]
pub use embed::{cosine, l2_normalize, EmbedEngine, EMBED_DIM, INPUT_SIZE};
pub use error::{InferError, Result};
#[cfg(not(feature = "types-only"))]
pub use icon_index::{EmbeddingIndex, IconIndex, IconMatch, IndexStorageFormat};
pub use manifest::{LicenseInfo, Manifest};
#[cfg(not(feature = "types-only"))]
pub use ocr::{OcrBounds, OcrConfig, OcrDetectionConfig, OcrEngine, OcrTimings, OcrWord};
#[cfg(not(feature = "types-only"))]
pub use registry::Registry;
pub use runtime::{BatchConfig, MnnConfig, OnnxConfig, OcrRecStrategy, RuntimeConfig};
