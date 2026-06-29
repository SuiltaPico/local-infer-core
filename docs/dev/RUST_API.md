# local-infer-core Rust API

本文档基于 `crates/infer-core` 当前代码整理，聚焦对外公开 API（`lib.rs` re-export 的能力）。

## 1. 对外模块与重导出

`infer_core` 对外公开：

- `embed`
- `error`
- `icon_index`
- `manifest`
- `ocr`
- `registry`
- `runtime`

常用重导出符号：

- `Registry`
- `RuntimeConfig` / `OnnxConfig` / `MnnConfig`
- `OcrEngine` / `OcrConfig` / `OcrWord` / `OcrTimings`
- `EmbedEngine` / `INPUT_SIZE` / `EMBED_DIM`
- `IconIndex` / `EmbeddingIndex` / `IconMatch` / `IndexStorageFormat`
- `Manifest` / `LicenseInfo`
- `InferError` / `Result<T>`

## 2. 注册表与模型包加载

## `Registry`

- `Registry::open(models_dir, runtime_config) -> Result<Registry>`
  - 扫描 `models_dir/*/manifest.json`
  - 校验目录名与 `manifest.id` 一致
  - 校验 license 文件存在且非空
- `models_dir(&self) -> &Path`
- `runtime_config(&self) -> &RuntimeConfig`
- `pack_ids(&self) -> impl Iterator<Item=&str>`
- `manifest(&self, pack_id: &str) -> Result<&Manifest>`
- `pack_dir(&self, pack_id: &str) -> Result<&Path>`
- `load_ocr(&self, pack_id: &str) -> Result<OcrEngine>`
- `load_embed(&self, pack_id: &str) -> Result<EmbedEngine>`
- `load_icon_index(&self, pack_id: &str) -> Result<IconIndex>`

## 3. Runtime 配置 API

## `RuntimeConfig`

- 结构：
  - `onnx: Option<OnnxConfig>`
  - `mnn: Option<MnnConfig>`
- 关键方法：
  - `RuntimeConfig::from_json(text: &str) -> Result<RuntimeConfig>`
  - `onnx_config(&self) -> OnnxConfig`
  - `mnn_config(&self) -> MnnConfig`
  - `resolved_eps(&self) -> Vec<String>`
    - 解析显式 `execution_providers`；含 `"auto"` 时按平台展开
    - 可自动追加 `cpu`（由 `append_cpu_fallback` 控制）
  - `prefer_gpu_single_session(&self) -> bool`

**不读环境变量。** 调用方通过 JSON / 结构体显式传入配置。

## `OnnxConfig`

- `execution_providers: Vec<String>`（默认 `["auto"]`）
- `intra_threads: Option<u32>`
- `inter_threads: Option<u32>`
- `append_cpu_fallback: bool`（默认 `true`）
- `gpu_single_session: bool`（默认 `true`）

## `MnnConfig`

- `backend: String`（默认 `"cpu"`）
- `num_thread: Option<u32>`
- `precision: String`（默认 `"normal"`）

## Runtime 能力探测

- `backend_kind() -> &'static str`（`"onnx"` 或 `"mnn"`）
- `available_backends() -> Vec<String>`

## 4. OCR API

## 主要类型

- `OcrConfig`
  - `min_confidence: f32`（默认 `0.5`）
  - `max_side: u32`（默认 `960`）
  - `detection: OcrDetectionConfig`
- `OcrDetectionConfig`
  - `score_threshold`
  - `box_threshold`
  - `unclip_ratio`
  - `from_manifest_value(&serde_json::Value) -> OcrDetectionConfig`
- `OcrWord`
  - `text: String`
  - `bounds: OcrBounds`
  - `confidence: f32`
- `OcrTimings`
  - `init_ms: f64`
  - `predict_ms: f64`
- `OcrBounds::new(x, y, width, height)`
- 辅助函数：
  - `resize_rgb_for_ocr(rgb, max_side)`
  - `scale_bounds(bounds, coord_scale)`

## `OcrEngine`（后端实现导出同名类型）

- `from_manifest(pack_dir, manifest, runtime_config) -> Result<OcrEngine>`
- `from_paths(det, rec, dict, config, runtime_config) -> Result<OcrEngine>`
- `apply_config_overrides(min_confidence, max_side)`
- `recognize(&self, image) -> Result<Vec<OcrWord>>`
- `recognize_timed(&self, image) -> Result<(Vec<OcrWord>, OcrTimings)>`
- `recognize_path(&self, image_path) -> Result<Vec<OcrWord>>`
- `recognize_rgb_timed(&self, rgb) -> Result<(Vec<OcrWord>, OcrTimings)>`
- `plain_text(&self, image) -> Result<String>`
- `plain_text_path(&self, image_path) -> Result<String>`

## 5. Embedding API

## 常量与工具函数

- `INPUT_SIZE: u32 = 256`
- `EMBED_DIM: usize = 512`
- `rgb256_to_nchw(rgb: &RgbImage) -> Vec<f32>`
- `l2_normalize(v: &mut [f32]) -> f32`
- `finalize_embedding(embedding: Vec<f32>) -> Result<Vec<f32>>`
- `cosine(a: &[f32], b: &[f32]) -> f64`

## `EmbedEngine`

- `from_manifest(pack_dir, manifest, runtime_config) -> Result<EmbedEngine>`
- `load(model_path, runtime_config) -> Result<EmbedEngine>`
- `embed_rgb256(&mut self, rgb: &RgbImage) -> Result<Vec<f32>>`
- `embed_nchw(&mut self, nchw: &[f32]) -> Result<Vec<f32>>`

说明：

- 输出向量会规整到 `EMBED_DIM` 并做 L2 归一化。
- `embed_nchw` 要求输入长度严格等于 `3 * 256 * 256`。

## 6. Icon Index API

## `IndexStorageFormat`

- `F32` / `Int8`
- `parse("f32"|"fp32"|"int8"|"i8")`
- `index_format_label() -> "mcl2-v1"|"mcl2-v2"`
- `from_index_version(version)`

## 顶层函数

- `read_file_storage_format(path) -> Result<IndexStorageFormat>`

## `EmbeddingIndex`

- 字段：`dim`、`names`
- 方法：
  - `count(&self) -> usize`
  - `from_float_vectors(dim, names, vectors) -> Result<EmbeddingIndex>`
  - `vector_f32(&self, index) -> Vec<f32>`
  - `best_match(&self, query) -> Option<(usize, f64)>`
  - `top_k(&self, query, k) -> Vec<(usize, f64)>`
  - `load(path) -> Result<EmbeddingIndex>`
  - `save(path) -> Result<()>`（默认存 Int8）
  - `save_as(path, format) -> Result<()>`

## `IconIndex`

- `from_manifest(pack_dir, manifest) -> Result<IconIndex>`
- `load(path) -> Result<IconIndex>`
- `embedding_index(&self) -> &EmbeddingIndex`
- `path(&self) -> &Path`
- `match_embedding(query, min_cosine) -> Option<IconMatch>`
- `search(query, top_k) -> Vec<IconMatch>`

## `IconMatch`

- `name: String`
- `score: f64`

## 7. Manifest API

## `Manifest`

- 关键字段：
  - `schema` / `id` / `kind`
  - `family` / `version` / `format` / `quant`
  - `files`（JSON 对象）
  - `license: Option<LicenseInfo>`
  - `inputs` / `detection` / `dim` / `embed_model_id`
- 方法：
  - `load_from_dir(pack_dir) -> Result<Manifest>`
  - `validate_license_files(pack_dir) -> Result<()>`
  - `file_path(pack_dir, key) -> Result<PathBuf>`
  - `validate_pack_files(pack_dir) -> Result<()>`

## `LicenseInfo`

- `spdx: String`
- `files: Vec<String>`
- `upstream: serde_json::Value`

## 8. 错误模型

统一错误类型：`InferError`

- `Manifest`
- `License`
- `PackNotFound`
- `Ocr`
- `Embed`
- `IconIndex`
- `Runtime`
- `Io`
- `Json`

公共结果别名：`type Result<T> = std::result::Result<T, InferError>`

## 9. 最小调用示例

```rust
use infer_core::{Registry, RuntimeConfig};

let cfg = RuntimeConfig::default();
let registry = Registry::open("D:/models", cfg)?;

let mut embed = registry.load_embed("embed.mobileclip2-s0.onnx.fp32")?;
let _index = registry.load_icon_index("icons.bundled.v1.mobileclip2-s0.int8")?;
let ocr = registry.load_ocr("ocr.paddle.ppocr6-tiny.onnx.fp32")?;
```
