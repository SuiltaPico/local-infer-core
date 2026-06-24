use std::path::PathBuf;

use infer_core::Registry;

#[test]
fn registry_loads_fixture_pack_with_license() {
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let registry = Registry::open(&fixtures, Default::default()).expect("open registry");
    assert!(registry
        .pack_ids()
        .any(|id| id == "ocr.paddle.ppocr6-tiny.onnx.fp32"));
}

#[test]
fn registry_validates_fixture_pack_files_when_present() {
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let pack_dir = fixtures.join("ocr.paddle.ppocr6-tiny.onnx.fp32");
    let det = pack_dir.join("det.onnx");
    if !det.is_file() {
        eprintln!("skip: run scripts/download_ppocr6_tiny_fixture.ps1");
        return;
    }
    let manifest = infer_core::Manifest::load_from_dir(&pack_dir).expect("load manifest");
    manifest
        .validate_pack_files(&pack_dir)
        .expect("validate pack files");
}

#[test]
fn registry_rejects_missing_license_file() {
    let dir = tempfile::tempdir().unwrap();
    let pack_dir = dir.path().join("test.pack.onnx.int8");
    std::fs::create_dir_all(&pack_dir).unwrap();
    std::fs::write(
        pack_dir.join("manifest.json"),
        r#"{
          "schema": 1,
          "id": "test.pack.onnx.int8",
          "kind": "ocr",
          "files": { "det": "det.onnx" },
          "license": {
            "spdx": "Apache-2.0",
            "files": ["LICENSE"],
            "upstream": { "name": "test" }
          }
        }"#,
    )
    .unwrap();

    let err = Registry::open(dir.path(), Default::default()).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("license"), "expected license error, got: {msg}");
}
