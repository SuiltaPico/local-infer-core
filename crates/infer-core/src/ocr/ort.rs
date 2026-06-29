use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use image::{DynamicImage, RgbImage};
use oar_ocr::domain::tasks::TextDetectionConfig;
use oar_ocr::oarocr::{OAROCR, OAROCRBuilder, TextRegion};
use oar_ocr::processors::BoundingBox;
use oar_ocr::utils::load_image;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::runtime::{self, RuntimeConfig};

use super::{
    scale_bounds, OcrBounds, OcrConfig, OcrDetectionConfig, OcrTimings, OcrWord,
};

pub struct OcrEngine {
    det: PathBuf,
    rec: PathBuf,
    dict: PathBuf,
    config: OcrConfig,
    runtime_config: RuntimeConfig,
}

impl OcrEngine {
    pub fn from_manifest(
        pack_dir: &Path,
        manifest: &Manifest,
        runtime_config: &RuntimeConfig,
    ) -> Result<Self> {
        let det = manifest.file_path(pack_dir, "det")?;
        let rec = manifest.file_path(pack_dir, "rec")?;
        let dict = manifest.file_path(pack_dir, "dict")?;
        let mut config = OcrConfig::default();
        if let Some(inputs) = manifest.inputs.as_ref().and_then(|v| v.as_object()) {
            if let Some(max_side) = inputs.get("det_max_side").and_then(|v| v.as_u64()) {
                config.max_side = max_side as u32;
            }
        }
        if let Some(detection) = &manifest.detection {
            config.detection = OcrDetectionConfig::from_manifest_value(detection);
        }
        Self::from_paths(det, rec, dict, config, runtime_config.clone())
    }

    /// Load OCR from explicit det/rec/dict paths.
    pub fn from_paths(
        det: PathBuf,
        rec: PathBuf,
        dict: PathBuf,
        config: OcrConfig,
        runtime_config: RuntimeConfig,
    ) -> Result<Self> {
        for path in [&det, &rec, &dict] {
            if !path.is_file() {
                return Err(InferError::Ocr(format!(
                    "OCR model file not found: {}",
                    path.display()
                )));
            }
        }
        Ok(Self {
            det,
            rec,
            dict,
            config,
            runtime_config,
        })
    }

    /// Override manifest defaults at runtime.
    pub fn apply_config_overrides(&mut self, min_confidence: Option<f32>, max_side: Option<u32>) {
        if let Some(v) = min_confidence {
            self.config.min_confidence = v;
        }
        if let Some(v) = max_side {
            self.config.max_side = v;
        }
    }

    pub fn recognize(&self, image: &DynamicImage) -> Result<Vec<OcrWord>> {
        self.recognize_timed(image).map(|(words, _)| words)
    }

    pub fn plain_text(&self, image: &DynamicImage) -> Result<String> {
        let words = self.recognize(image)?;
        Ok(words
            .into_iter()
            .map(|w| w.text)
            .collect::<Vec<_>>()
            .join("\n"))
    }

    pub fn plain_text_path(&self, image_path: &Path) -> Result<String> {
        let words = self.recognize_path(image_path)?;
        Ok(words
            .into_iter()
            .map(|w| w.text)
            .collect::<Vec<_>>()
            .join("\n"))
    }

    pub fn recognize_timed(&self, image: &DynamicImage) -> Result<(Vec<OcrWord>, OcrTimings)> {
        let rgb = image.to_rgb8();
        self.recognize_rgb_timed(rgb)
    }

    pub fn recognize_path(&self, image_path: &Path) -> Result<Vec<OcrWord>> {
        let rgb = load_image(image_path).map_err(|e| InferError::Ocr(e.to_string()))?;
        self.recognize_rgb_timed(rgb).map(|(words, _)| words)
    }

    pub fn recognize_rgb_timed(&self, rgb: RgbImage) -> Result<(Vec<OcrWord>, OcrTimings)> {
        use super::resize::resize_rgb_for_ocr;

        let mut timings = OcrTimings::default();
        let (rgb, coord_scale) = resize_rgb_for_ocr(rgb, self.config.max_side);

        let det_cfg = self.config.detection.to_oar_config(self.config.max_side);
        let key = format!(
            "{}|{}|{}|{:.3}|{:.3}|{:.3}|{}",
            self.det.display(),
            self.rec.display(),
            self.dict.display(),
            det_cfg.score_threshold,
            det_cfg.box_threshold,
            det_cfg.unclip_ratio,
            self.config.max_side,
        );

        let mut guard = engine_cache()
            .lock()
            .map_err(|e| InferError::Ocr(format!("OCR engine lock poisoned: {e}")))?;

        let needs_rebuild = guard
            .as_ref()
            .map(|cached| cached.key != key)
            .unwrap_or(true);

        if needs_rebuild {
            let init_start = Instant::now();
            let mut builder = OAROCRBuilder::new(&self.det, &self.rec, &self.dict)
                .text_detection_config(det_cfg);
            if let Some(ort_config) = runtime::oar_session_config("OCR", &self.runtime_config) {
                builder = builder.ort_session(ort_config);
            }
            let engine = builder
                .build()
                .map_err(|e| InferError::Ocr(e.to_string()))?;
            timings.init_ms = ms_since(init_start);
            *guard = Some(CachedOcr { key, engine });
        }

        let predict_start = Instant::now();
        let engine = &guard.as_ref().expect("engine initialized").engine;
        let results = engine
            .predict(vec![rgb])
            .map_err(|e| InferError::Ocr(e.to_string()))?;
        timings.predict_ms = ms_since(predict_start);

        let Some(result) = results.into_iter().next() else {
            return Ok((vec![], timings));
        };

        let mut words = Vec::new();
        for region in result.text_regions {
            words.extend(region_to_words(&region, self.config.min_confidence));
        }
        if coord_scale != 1.0 {
            for word in &mut words {
                word.bounds = scale_bounds(word.bounds, coord_scale);
            }
        }
        Ok((words, timings))
    }
}

impl OcrDetectionConfig {
    fn to_oar_config(&self, max_side: u32) -> TextDetectionConfig {
        TextDetectionConfig {
            score_threshold: self.score_threshold,
            box_threshold: self.box_threshold,
            unclip_ratio: self.unclip_ratio,
            max_candidates: 1000,
            limit_side_len: Some(max_side),
            limit_type: None,
            max_side_len: Some(max_side),
        }
    }
}

struct CachedOcr {
    key: String,
    engine: OAROCR,
}

fn engine_cache() -> &'static Mutex<Option<CachedOcr>> {
    static ENGINE: OnceLock<Mutex<Option<CachedOcr>>> = OnceLock::new();
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn region_to_words(region: &TextRegion, min_confidence: f32) -> Vec<OcrWord> {
    let Some(text) = region.text.as_ref().map(|t| t.trim()).filter(|t| !t.is_empty()) else {
        return vec![];
    };

    let confidence = region.confidence.unwrap_or(0.0);
    if confidence < min_confidence {
        return vec![];
    }

    let display_confidence = confidence * 100.0;

    if let Some(word_boxes) = &region.word_boxes {
        if !word_boxes.is_empty() {
            return word_boxes_to_words(text, word_boxes, display_confidence, min_confidence);
        }
    }

    vec![OcrWord {
        text: text.to_string(),
        bounds: bbox_to_bounds(&region.bounding_box),
        confidence: display_confidence,
    }]
}

fn word_boxes_to_words(
    text: &str,
    word_boxes: &[BoundingBox],
    line_confidence: f32,
    min_confidence: f32,
) -> Vec<OcrWord> {
    if line_confidence < min_confidence * 100.0 {
        return vec![];
    }

    let tokens: Vec<&str> = text.split_whitespace().collect();
    if tokens.len() == word_boxes.len() {
        return tokens
            .iter()
            .zip(word_boxes.iter())
            .map(|(token, bbox)| OcrWord {
                text: (*token).to_string(),
                bounds: bbox_to_bounds(bbox),
                confidence: line_confidence,
            })
            .collect();
    }

    if word_boxes.len() == text.chars().count() {
        return word_boxes
            .iter()
            .zip(text.chars())
            .map(|(bbox, ch)| OcrWord {
                text: ch.to_string(),
                bounds: bbox_to_bounds(bbox),
                confidence: line_confidence,
            })
            .collect();
    }

    vec![OcrWord {
        text: text.to_string(),
        bounds: bbox_to_bounds(&word_boxes[0]),
        confidence: line_confidence,
    }]
}

fn bbox_to_bounds(bbox: &BoundingBox) -> OcrBounds {
    let x_min = bbox.x_min();
    let y_min = bbox.y_min();
    let x_max = bbox.x_max();
    let y_max = bbox.y_max();
    let width = (x_max - x_min).round().max(1.0) as i32;
    let height = (y_max - y_min).round().max(1.0) as i32;
    OcrBounds::new(x_min.round() as i32, y_min.round() as i32, width, height)
}

fn ms_since(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn bbox_to_bounds_uses_axis_aligned_box() {
        let bbox = BoundingBox::from_coords(10.2, 20.7, 50.9, 40.1);
        let bounds = bbox_to_bounds(&bbox);
        assert_eq!(bounds.x, 10);
        assert_eq!(bounds.y, 21);
        assert_eq!(bounds.width, 41);
        assert_eq!(bounds.height, 19);
    }

    #[test]
    fn region_to_words_skips_low_confidence() {
        let region = TextRegion::with_recognition(
            BoundingBox::from_coords(0.0, 0.0, 10.0, 10.0),
            Some(Arc::from("hello")),
            Some(0.2),
        );
        assert!(region_to_words(&region, 0.5).is_empty());
    }
}
