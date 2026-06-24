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
pub use runtime::{OnnxConfig, RuntimeConfig};
