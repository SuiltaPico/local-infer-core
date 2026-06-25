use std::path::PathBuf;

use infer_core_lib::{OnnxConfig, Registry, RuntimeConfig};

const PACK_ID: &str = "ocr.paddle.ppocr6-tiny.onnx.fp32";

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn pack_dir() -> PathBuf {
    fixtures_dir().join(PACK_ID)
}

fn models_ready() -> bool {
    let dir = pack_dir();
    dir.join("det.onnx").is_file()
        && dir.join("rec.onnx").is_file()
        && dir.join("ppocrv6_tiny_dict.txt").is_file()
}

#[test]
fn ocr_v6_plain_text_non_empty() {
    if !models_ready() {
        eprintln!(
            "skip ocr_v6_plain_text_non_empty: run scripts/download_ppocr6_tiny_fixture.ps1"
        );
        return;
    }

    let sample = fixtures_dir().join("sample_ocr.jpg");
    assert!(
        sample.is_file(),
        "missing sample image at {}; run scripts/download_ppocr6_tiny_fixture.ps1",
        sample.display()
    );

    let runtime = RuntimeConfig {
        onnx: Some(OnnxConfig {
            execution_providers: vec!["cpu".into()],
            append_cpu_fallback: false,
            ..Default::default()
        }),
        ..Default::default()
    };
    let registry = Registry::open(fixtures_dir(), runtime).expect("open registry");
    let ocr = registry.load_ocr(PACK_ID).expect("load ocr pack");

    let text = ocr
        .plain_text_path(&sample)
        .expect("ocr plain_text");
    assert!(
        !text.trim().is_empty(),
        "expected non-empty OCR text, got: {text:?}"
    );
}
