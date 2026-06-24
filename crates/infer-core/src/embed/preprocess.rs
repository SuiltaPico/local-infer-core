//! Template PNG preprocessing for MobileCLIP2 icon embedding.

use image::{DynamicImage, Rgb, RgbImage};

use super::{INPUT_SIZE, EMBED_DIM};

pub use super::rgb256_to_nchw;

/// Render a template PNG (RGBA + alpha) as 256×256 RGB for embedding index build.
pub fn template_png_to_rgb256(img: &DynamicImage, mask_size: u32) -> RgbImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let mut flat = RgbImage::new(w, h);
    for y in 0..h {
        for x in 0..w {
            flat.put_pixel(x, y, composite_icon_pixel(rgba.get_pixel(x, y)));
        }
    }

    let mut resized = if w == mask_size && h == mask_size {
        flat
    } else {
        image::imageops::resize(
            &flat,
            mask_size,
            mask_size,
            image::imageops::FilterType::Triangle,
        )
    };

    if mask_size != INPUT_SIZE {
        resized = image::imageops::resize(
            &resized,
            INPUT_SIZE,
            INPUT_SIZE,
            image::imageops::FilterType::Triangle,
        );
    }
    resized
}

fn composite_icon_pixel(pixel: &image::Rgba<u8>) -> Rgb<u8> {
    let alpha = pixel[3] as f32 / 255.0;
    let blend = |channel: u8| {
        (channel as f32 * alpha + 255.0 * (1.0 - alpha))
            .round()
            .clamp(0.0, 255.0) as u8
    };
    Rgb([blend(pixel[0]), blend(pixel[1]), blend(pixel[2])])
}

#[allow(dead_code)]
pub fn embed_dim() -> usize {
    EMBED_DIM
}
