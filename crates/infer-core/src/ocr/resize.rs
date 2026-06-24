use image::RgbImage;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OcrBounds {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl OcrBounds {
    pub fn new(x: i32, y: i32, width: i32, height: i32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }
}

pub fn resize_rgb_for_ocr(rgb: RgbImage, max_side: u32) -> (RgbImage, f32) {
    if max_side == 0 {
        return (rgb, 1.0);
    }

    let (width, height) = rgb.dimensions();
    let longest = width.max(height);
    if longest <= max_side {
        return (rgb, 1.0);
    }

    let scale = max_side as f32 / longest as f32;
    let new_width = ((width as f32 * scale).round() as u32).max(1);
    let new_height = ((height as f32 * scale).round() as u32).max(1);
    let resized = image::imageops::resize(
        &rgb,
        new_width,
        new_height,
        image::imageops::FilterType::Triangle,
    );
    let coord_scale = width as f32 / new_width as f32;
    (resized, coord_scale)
}

pub fn scale_bounds(bounds: OcrBounds, coord_scale: f32) -> OcrBounds {
    if coord_scale == 1.0 {
        return bounds;
    }

    OcrBounds::new(
        (bounds.x as f32 * coord_scale).round() as i32,
        (bounds.y as f32 * coord_scale).round() as i32,
        (bounds.width as f32 * coord_scale).round().max(1.0) as i32,
        (bounds.height as f32 * coord_scale).round().max(1.0) as i32,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resize_rgb_for_ocr_keeps_small_images() {
        let rgb = RgbImage::new(800, 600);
        let (out, scale) = resize_rgb_for_ocr(rgb, 960);
        assert_eq!(out.dimensions(), (800, 600));
        assert_eq!(scale, 1.0);
    }

    #[test]
    fn resize_rgb_for_ocr_scales_long_edge() {
        let rgb = RgbImage::new(1920, 873);
        let (out, scale) = resize_rgb_for_ocr(rgb, 960);
        assert_eq!(out.dimensions(), (960, 437));
        assert!((scale - 2.0).abs() < 0.01);
    }
}
