mod resize;

pub use resize::{resize_rgb_for_ocr, scale_bounds, OcrBounds};

#[derive(Debug, Clone)]
pub struct OcrConfig {
    /// Recognition confidence filter applied after OCR (0–100 scale internally).
    pub min_confidence: f32,
    pub max_side: u32,
    pub detection: OcrDetectionConfig,
}

#[derive(Debug, Clone)]
pub struct OcrDetectionConfig {
    pub score_threshold: f32,
    pub box_threshold: f32,
    pub unclip_ratio: f32,
}

impl Default for OcrDetectionConfig {
    fn default() -> Self {
        Self {
            score_threshold: 0.3,
            box_threshold: 0.6,
            unclip_ratio: 1.5,
        }
    }
}

impl OcrDetectionConfig {
    pub fn from_manifest_value(value: &serde_json::Value) -> Self {
        let mut cfg = Self::default();
        let Some(obj) = value.as_object() else {
            return cfg;
        };
        if let Some(v) = obj.get("score_threshold").and_then(|v| v.as_f64()) {
            cfg.score_threshold = v as f32;
        }
        if let Some(v) = obj.get("box_threshold").and_then(|v| v.as_f64()) {
            cfg.box_threshold = v as f32;
        }
        if let Some(v) = obj.get("unclip_ratio").and_then(|v| v.as_f64()) {
            cfg.unclip_ratio = v as f32;
        }
        cfg
    }
}

impl Default for OcrConfig {
    fn default() -> Self {
        Self {
            min_confidence: 0.5,
            max_side: 960,
            detection: OcrDetectionConfig::default(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct OcrWord {
    pub text: String,
    pub bounds: OcrBounds,
    pub confidence: f32,
}

#[derive(Debug, Clone, Default)]
pub struct OcrTimings {
    pub init_ms: f64,
    pub predict_ms: f64,
    /// Requested MNN backend (`RuntimeConfig`, after resolving `"auto"`).
    pub mnn_configured_backend: Option<String>,
    /// Backends reported by MNN for the OCR session (`getSessionInfo` / `BACKENDS`).
    pub mnn_session_backends: Vec<String>,
}

#[cfg(feature = "backend-ort")]
mod ort;
#[cfg(feature = "backend-ort")]
pub use ort::OcrEngine;

#[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
mod mnn;
#[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
pub use mnn::{clear_engine_cache, OcrEngine};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detection_config_from_manifest() {
        let json = serde_json::json!({
            "score_threshold": 0.2,
            "box_threshold": 0.45,
            "unclip_ratio": 1.4
        });
        let cfg = OcrDetectionConfig::from_manifest_value(&json);
        assert!((cfg.score_threshold - 0.2).abs() < f32::EPSILON);
        assert!((cfg.box_threshold - 0.45).abs() < f32::EPSILON);
        assert!((cfg.unclip_ratio - 1.4).abs() < f32::EPSILON);
    }
}
