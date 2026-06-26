use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use image::{DynamicImage, GrayImage, RgbImage};
use imageproc::contours::find_contours;

use crate::error::{InferError, Result};
use crate::manifest::Manifest;
use crate::mnn_util::{self, MnnModel};
use crate::runtime::RuntimeConfig;

use super::{
    resize::resize_rgb_for_ocr, scale_bounds, OcrBounds, OcrConfig, OcrDetectionConfig, OcrTimings,
    OcrWord,
};

const DET_STRIDE: u32 = 32;

pub struct OcrEngine {
    det: PathBuf,
    rec: PathBuf,
    dict: PathBuf,
    config: OcrConfig,
    rec_height: u32,
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
        let mut rec_height = 48u32;
        if let Some(inputs) = manifest.inputs.as_ref().and_then(|v| v.as_object()) {
            if let Some(max_side) = inputs.get("det_max_side").and_then(|v| v.as_u64()) {
                config.max_side = max_side as u32;
            }
            if let Some(h) = inputs.get("rec_height").and_then(|v| v.as_u64()) {
                rec_height = h as u32;
            }
        }
        if let Some(detection) = &manifest.detection {
            config.detection = OcrDetectionConfig::from_manifest_value(detection);
        }
        Self::from_paths(det, rec, dict, config, rec_height, runtime_config.clone())
    }

    pub fn from_paths(
        det: PathBuf,
        rec: PathBuf,
        dict: PathBuf,
        config: OcrConfig,
        rec_height: u32,
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
            rec_height,
            runtime_config,
        })
    }

    /// Override manifest defaults (e.g. ui-extractor CLI flags).
    pub fn apply_config_overrides(&mut self, min_confidence: Option<f32>, max_side: Option<u32>) {
        if let Some(v) = min_confidence {
            self.config.min_confidence = v;
        }
        if let Some(v) = max_side {
            self.config.max_side = v;
        }
    }

    #[deprecated(note = "use Registry::load_ocr with manifest-driven pack layout")]
    pub fn from_model_dir(
        model_dir: &Path,
        config: OcrConfig,
        runtime_config: RuntimeConfig,
    ) -> Result<Self> {
        let v6_det = model_dir.join("pp-ocrv6_tiny_det.mnn");
        if v6_det.is_file() {
            return Self::from_paths(
                v6_det,
                model_dir.join("pp-ocrv6_tiny_rec.mnn"),
                model_dir.join("ppocrv6_tiny_dict.txt"),
                config,
                48,
                runtime_config,
            );
        }
        Self::from_paths(
            model_dir.join("det.mnn"),
            model_dir.join("rec.mnn"),
            model_dir.join("ppocrv6_dict.txt"),
            config,
            48,
            runtime_config,
        )
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
        self.recognize_rgb_timed(image.to_rgb8())
    }

    pub fn recognize_path(&self, image_path: &Path) -> Result<Vec<OcrWord>> {
        let rgb = image::open(image_path)
            .map_err(|e| InferError::Ocr(e.to_string()))?
            .to_rgb8();
        self.recognize_rgb_timed(rgb).map(|(words, _)| words)
    }

    pub fn recognize_rgb_timed(&self, rgb: RgbImage) -> Result<(Vec<OcrWord>, OcrTimings)> {
        let mut timings = OcrTimings::default();
        let (rgb, coord_scale) = resize_rgb_for_ocr(rgb, self.config.max_side);

        let key = format!(
            "{}|{}|{}",
            self.det.display(),
            self.rec.display(),
            self.dict.display()
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
            let det = MnnModel::load(&self.det, &self.runtime_config, "ocr-det")?;
            let rec = MnnModel::load(&self.rec, &self.runtime_config, "ocr-rec")?;
            let dict = load_dict(&self.dict)?;
            timings.init_ms = ms_since(init_start);
            *guard = Some(CachedOcr {
                key,
                det,
                rec,
                dict,
            });
        }

        let predict_start = Instant::now();
        let engine = guard.as_mut().expect("engine initialized");
        let boxes = detect_text_boxes(
            &mut engine.det,
            &rgb,
            self.config.max_side,
            &self.config.detection,
        )?;

        let mut words = Vec::new();
        for bbox in boxes {
            let text = recognize_crop(
                &mut engine.rec,
                &engine.dict,
                &rgb,
                &bbox,
                self.rec_height,
            )?;
            if text.is_empty() {
                continue;
            }
            let confidence = 100.0;
            if confidence / 100.0 < self.config.min_confidence {
                continue;
            }
            words.push(OcrWord {
                text,
                bounds: bbox,
                confidence,
            });
        }
        timings.predict_ms = ms_since(predict_start);

        if coord_scale != 1.0 {
            for word in &mut words {
                word.bounds = scale_bounds(word.bounds, coord_scale);
            }
        }
        Ok((words, timings))
    }
}

struct CachedOcr {
    key: String,
    det: MnnModel,
    rec: MnnModel,
    dict: Vec<String>,
}

fn engine_cache() -> &'static Mutex<Option<CachedOcr>> {
    static ENGINE: OnceLock<Mutex<Option<CachedOcr>>> = OnceLock::new();
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn load_dict(path: &Path) -> Result<Vec<String>> {
    let raw = fs::read_to_string(path).map_err(|e| InferError::Ocr(e.to_string()))?;
    Ok(raw.lines().map(|line| line.to_string()).collect())
}

struct DetContext {
    scale: f32,
    pad_left: u32,
    pad_top: u32,
}

fn detect_text_boxes(
    model: &mut MnnModel,
    rgb: &RgbImage,
    det_max_side: u32,
    detection: &OcrDetectionConfig,
) -> Result<Vec<OcrBounds>> {
    let (img_w, img_h) = rgb.dimensions();
    let mut w = img_w;
    let mut h = img_h;
    let mut scale = 1.0f32;

    let target = w.max(h).min(det_max_side);
    if w.max(h) > target {
        if w > h {
            scale = target as f32 / w as f32;
            w = target;
            h = ((img_h as f32 * scale).round() as u32).max(1);
        } else {
            scale = target as f32 / h as f32;
            h = target;
            w = ((img_w as f32 * scale).round() as u32).max(1);
        }
    }

    let resized = if w == img_w && h == img_h {
        rgb.clone()
    } else {
        image::imageops::resize(rgb, w, h, image::imageops::FilterType::Triangle)
    };

    let pad_w = ((w + DET_STRIDE - 1) / DET_STRIDE) * DET_STRIDE;
    let pad_h = ((h + DET_STRIDE - 1) / DET_STRIDE) * DET_STRIDE;
    let pad_left = (pad_w - w) / 2;
    let pad_top = (pad_h - h) / 2;
    let pad_right = pad_w - w - pad_left;
    let pad_bottom = pad_h - h - pad_top;

    let padded = pad_rgb(&resized, pad_left, pad_top, pad_right, pad_bottom, 114);
    let nchw = mnn_util::rgb_to_nchw_imagenet(&padded);
    let input_name = model.input_name.clone();
    let output_name = model.output_name.clone();

    let mut input = unsafe { model.interpreter.input_unresized::<f32>(&model.session, &input_name) }
        .map_err(|e| mnn_util::map_err("ocr-det", e))?;
    model
        .interpreter
        .resize_tensor_by_nchw(&mut input, 1, 3, pad_h as u16, pad_w as u16);
    drop(input);
    model.interpreter.resize_session(&mut model.session);

    let mut input = model
        .interpreter
        .input(&model.session, &input_name)
        .map_err(|e| mnn_util::map_err("ocr-det", e))?;
    let mut host = input.create_host_tensor_from_device(false);
    host.host_mut().copy_from_slice(&nchw);
    input
        .copy_from_host_tensor(&host)
        .map_err(|e| mnn_util::map_err("ocr-det", e))?;
    drop(input);

    model
        .interpreter
        .run_session(&model.session)
        .map_err(|e| mnn_util::map_err("ocr-det", e))?;

    let probs = mnn_util::read_output_f32(
        &model.interpreter,
        &model.session,
        &output_name,
        "ocr-det",
    )?;
    let output = model
        .interpreter
        .output(&model.session, &output_name)
        .map_err(|e| mnn_util::map_err("ocr-det", e))?;
    let (prob_h, prob_w) = prob_map_dims(&output);
    let ctx = DetContext {
        scale,
        pad_left,
        pad_top,
    };

    boxes_from_prob_map(
        &probs,
        prob_w,
        prob_h,
        &ctx,
        detection.score_threshold,
        detection.box_threshold,
        detection.unclip_ratio,
    )
}

fn prob_map_dims(output: &mnn::Tensor<mnn::Ref<'_, mnn::Device<f32>>>) -> (u32, u32) {
    let shape = output.shape();
    let dims: Vec<i32> = shape.as_ref().to_vec();
    match dims.as_slice() {
        [_, _, h, w] | [_, h, w] => (*h as u32, *w as u32),
        [h, w] => (*h as u32, *w as u32),
        _ => (output.height(), output.width()),
    }
}

fn pad_rgb(
    img: &RgbImage,
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
    value: u8,
) -> RgbImage {
    let (w, h) = img.dimensions();
    let out_w = w + left + right;
    let out_h = h + top + bottom;
    let fill = image::Rgb([value, value, value]);
    let mut out = RgbImage::from_pixel(out_w, out_h, fill);
    for y in 0..h {
        for x in 0..w {
            out.put_pixel(x + left, y + top, *img.get_pixel(x, y));
        }
    }
    out
}

fn boxes_from_prob_map(
    probs: &[f32],
    width: u32,
    height: u32,
    ctx: &DetContext,
    score_threshold: f32,
    box_threshold: f32,
    unclip_ratio: f32,
) -> Result<Vec<OcrBounds>> {
    let mut binary = GrayImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let p = probs[(y * width + x) as usize];
            let v = if p >= score_threshold {
                255u8
            } else {
                0u8
            };
            binary.put_pixel(x, y, image::Luma([v]));
        }
    }

    let contours = find_contours::<u32>(&binary);
    let min_size = (3.0 * ctx.scale).max(3.0);
    let mut boxes = Vec::new();

    for contour in contours {
        if contour.points.len() <= 2 {
            continue;
        }
        let score = contour_mean_score(probs, width, height, &contour.points);
        if score < box_threshold {
            continue;
        }

        let (x0, y0, x1, y1) = contour_aabb(&contour.points);
        let bw = (x1 - x0) as f32;
        let bh = (y1 - y0) as f32;
        if bw.max(bh) < min_size {
            continue;
        }

        let cx = (x0 + x1) as f32 / 2.0;
        let cy = (y0 + y1) as f32 / 2.0;
        let mut w = bw * unclip_ratio;
        let mut h = bh * unclip_ratio;
        w = w.max(h * 0.3);
        h = h.max(w * 0.3);

        let mut x = cx - w / 2.0;
        let mut y = cy - h / 2.0;

        x = (x - ctx.pad_left as f32) / ctx.scale;
        y = (y - ctx.pad_top as f32) / ctx.scale;
        w /= ctx.scale;
        h /= ctx.scale;

        boxes.push(OcrBounds::new(
            x.round() as i32,
            y.round() as i32,
            w.round().max(1.0) as i32,
            h.round().max(1.0) as i32,
        ));
    }

    Ok(boxes)
}

fn contour_mean_score(
    probs: &[f32],
    width: u32,
    height: u32,
    points: &[imageproc::point::Point<u32>],
) -> f32 {
    if points.is_empty() {
        return 0.0;
    }
    let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
    for p in points {
        x0 = x0.min(p.x);
        y0 = y0.min(p.y);
        x1 = x1.max(p.x);
        y1 = y1.max(p.y);
    }
    if x1 <= x0 || y1 <= y0 {
        return 0.0;
    }

    let mut sum = 0.0f32;
    let mut count = 0u32;
    for y in y0..=y1.min(height - 1) {
        for x in x0..=x1.min(width - 1) {
            if point_in_contour(x, y, points) {
                sum += probs[(y * width + x) as usize];
                count += 1;
            }
        }
    }
    if count == 0 {
        0.0
    } else {
        sum / count as f32
    }
}

fn point_in_contour(x: u32, y: u32, points: &[imageproc::point::Point<u32>]) -> bool {
    let mut inside = false;
    let n = points.len();
    for i in 0..n {
        let j = (i + n - 1) % n;
        let pi = points[i];
        let pj = points[j];
        let x_cross = (pj.x as f64 - pi.x as f64) * (y as f64 - pi.y as f64)
            / (pj.y as f64 - pi.y as f64 + f64::EPSILON)
            + pi.x as f64;
        let intersect = ((pi.y > y) != (pj.y > y)) && (x as f64) < x_cross;
        if intersect {
            inside = !inside;
        }
    }
    inside
}

fn contour_aabb(points: &[imageproc::point::Point<u32>]) -> (u32, u32, u32, u32) {
    let mut x0 = u32::MAX;
    let mut y0 = u32::MAX;
    let mut x1 = 0u32;
    let mut y1 = 0u32;
    for p in points {
        x0 = x0.min(p.x);
        y0 = y0.min(p.y);
        x1 = x1.max(p.x);
        y1 = y1.max(p.y);
    }
    (x0, y0, x1, y1)
}

fn recognize_crop(
    model: &mut MnnModel,
    dict: &[String],
    rgb: &RgbImage,
    bounds: &OcrBounds,
    rec_height: u32,
) -> Result<String> {
    let crop = crop_rgb(rgb, bounds);
    if crop.width() == 0 || crop.height() == 0 {
        return Ok(String::new());
    }

    let (cw, ch) = crop.dimensions();
    let target_w = ((cw as f32 * rec_height as f32 / ch as f32).round() as u32).max(1);
    let resized = if ch == rec_height && cw == target_w {
        crop
    } else {
        image::imageops::resize(
            &crop,
            target_w,
            rec_height,
            image::imageops::FilterType::Triangle,
        )
    };

    let nchw = mnn_util::rgb_to_nchw_rec(&resized);
    let input_name = model.input_name.clone();
    let output_name = model.output_name.clone();

    let mut input = unsafe { model.interpreter.input_unresized::<f32>(&model.session, &input_name) }
        .map_err(|e| mnn_util::map_err("ocr-rec", e))?;
    model
        .interpreter
        .resize_tensor_by_nchw(&mut input, 1, 3, rec_height as u16, target_w as u16);
    drop(input);
    model.interpreter.resize_session(&mut model.session);

    let mut input = model
        .interpreter
        .input(&model.session, &input_name)
        .map_err(|e| mnn_util::map_err("ocr-rec", e))?;
    let mut host = input.create_host_tensor_from_device(false);
    host.host_mut().copy_from_slice(&nchw);
    input
        .copy_from_host_tensor(&host)
        .map_err(|e| mnn_util::map_err("ocr-rec", e))?;
    drop(input);

    model
        .interpreter
        .run_session(&model.session)
        .map_err(|e| mnn_util::map_err("ocr-rec", e))?;

    let logits = mnn_util::read_output_f32(
        &model.interpreter,
        &model.session,
        &output_name,
        "ocr-rec",
    )?;
    let output = model
        .interpreter
        .output(&model.session, &output_name)
        .map_err(|e| mnn_util::map_err("ocr-rec", e))?;
    let (time_steps, num_classes) = ctc_dims(&output);

    Ok(decode_ctc(&logits, time_steps, num_classes, dict))
}

fn ctc_dims(output: &mnn::Tensor<mnn::Ref<'_, mnn::Device<f32>>>) -> (usize, usize) {
    let shape = output.shape();
    let dims: Vec<i32> = shape.as_ref().to_vec();
    match dims.as_slice() {
        [_, t, c] => (*t as usize, *c as usize),
        [t, c] => (*t as usize, *c as usize),
        _ => (output.height() as usize, output.width() as usize),
    }
}

fn decode_ctc(data: &[f32], time_steps: usize, num_classes: usize, dict: &[String]) -> String {
    if time_steps == 0 || num_classes == 0 {
        return String::new();
    }

    let mut text = String::new();
    let mut last_token = 0usize;

    for t in 0..time_steps {
        let row = &data[t * num_classes..(t + 1) * num_classes];
        let (mut best_idx, mut best_score) = (0usize, f32::NEG_INFINITY);
        for (j, &score) in row.iter().enumerate().take(num_classes) {
            if score > best_score {
                best_score = score;
                best_idx = j;
            }
        }

        if best_idx == last_token {
            continue;
        }
        last_token = best_idx;
        if best_idx == 0 {
            continue;
        }
        let dict_idx = best_idx - 1;
        if dict_idx < dict.len() {
            text.push_str(&dict[dict_idx]);
        }
    }

    text
}

fn crop_rgb(rgb: &RgbImage, bounds: &OcrBounds) -> RgbImage {
    let (img_w, img_h) = rgb.dimensions();
    let x0 = bounds.x.max(0) as u32;
    let y0 = bounds.y.max(0) as u32;
    let x1 = (bounds.x + bounds.width).min(img_w as i32) as u32;
    let y1 = (bounds.y + bounds.height).min(img_h as i32) as u32;
    if x1 <= x0 || y1 <= y0 {
        return RgbImage::new(0, 0);
    }

    let w = x1 - x0;
    let h = y1 - y0;
    let mut out = RgbImage::new(w, h);
    for y in 0..h {
        for x in 0..w {
            out.put_pixel(x, y, *rgb.get_pixel(x0 + x, y0 + y));
        }
    }
    out
}

fn ms_since(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}
