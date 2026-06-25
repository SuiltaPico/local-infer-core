pub mod preprocess;

pub const INPUT_SIZE: u32 = 256;
pub const EMBED_DIM: usize = 512;

/// Convert RGB 256×256 to NCHW float tensor in [0, 1].
pub fn rgb256_to_nchw(rgb: &image::RgbImage) -> Vec<f32> {
    debug_assert_eq!(rgb.dimensions(), (INPUT_SIZE, INPUT_SIZE));
    let mut out = vec![0.0f32; 3 * INPUT_SIZE as usize * INPUT_SIZE as usize];
    let plane = (INPUT_SIZE * INPUT_SIZE) as usize;
    for y in 0..INPUT_SIZE {
        for x in 0..INPUT_SIZE {
            let pixel = rgb.get_pixel(x, y);
            let idx = (y * INPUT_SIZE + x) as usize;
            out[idx] = pixel[0] as f32 / 255.0;
            out[plane + idx] = pixel[1] as f32 / 255.0;
            out[2 * plane + idx] = pixel[2] as f32 / 255.0;
        }
    }
    out
}

pub fn l2_normalize(v: &mut [f32]) -> f32 {
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > f32::EPSILON {
        for x in v {
            *x /= norm;
        }
    }
    norm
}

pub fn finalize_embedding(mut embedding: Vec<f32>) -> crate::error::Result<Vec<f32>> {
    use crate::error::InferError;

    if embedding.len() > EMBED_DIM {
        embedding.truncate(EMBED_DIM);
    }
    if embedding.len() < EMBED_DIM {
        return Err(InferError::Embed(format!(
            "embedding dim {} < expected {EMBED_DIM}",
            embedding.len()
        )));
    }
    l2_normalize(&mut embedding);
    Ok(embedding)
}

pub fn cosine(a: &[f32], b: &[f32]) -> f64 {
    debug_assert_eq!(a.len(), b.len());
    a.iter()
        .zip(b.iter())
        .map(|(x, y)| (*x as f64) * (*y as f64))
        .sum()
}

#[cfg(feature = "backend-ort")]
mod ort;
#[cfg(feature = "backend-ort")]
pub use ort::EmbedEngine;

#[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
mod mnn;
#[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
pub use mnn::EmbedEngine;

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    #[test]
    fn rgb256_tensor_range() {
        let rgb = image::RgbImage::from_pixel(INPUT_SIZE, INPUT_SIZE, Rgb([128, 64, 32]));
        let tensor = rgb256_to_nchw(&rgb);
        assert!((tensor[0] - 128.0 / 255.0).abs() < 1e-6);
        assert_eq!(tensor.len(), 3 * INPUT_SIZE as usize * INPUT_SIZE as usize);
    }
}
