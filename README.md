# local-infer-core

Mauchat 生态的通用本地推理内核：OCR、图片嵌入，manifest 驱动，ONNX（桌面）+ MNN（移动端）。

| 文档 | 读者 |
|------|------|
| **[IMPLEMENTATION.md](IMPLEMENTATION.md)** | **接下来实现的 AI / 开发者 — 从这里开始** |
| [PRODUCT.md](PRODUCT.md) | 最终产品目标与契约 |

Dart 包：**`local_infer_core`**（本仓库 `dart/`，待建）— Mauchat 本地 OCR / 模型管理入口。

相关仓库：[ui-extractor](../ui-extractor/PRODUCT.md) · [Mauchat](../mauchat/PRODUCT.md)

> Phase 0–1 已落地：`infer-core` workspace、manifest/registry、OCR/embed/icon_index；`ui-extractor` 已 path 依赖 `infer-core`。

## 开发

- **Rust 1.95+**（见 `rust-toolchain.toml`；`oar-ocr 0.7` 需要）
- OCR 集成测试权重：`scripts/download_ppocr6_tiny_fixture.ps1`
- 校验样例包：`tools/pack/pack.ps1 -PackDir crates/infer-core/tests/fixtures/ocr.paddle.ppocr6-tiny.onnx.int8`
