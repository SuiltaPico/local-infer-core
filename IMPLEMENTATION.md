# 实现者上手（给 AI / 开发者）

**你接手时请先读完本文，再读 [PRODUCT.md](PRODUCT.md)。**  
本文是「今天代码在哪、已决定什么、按什么顺序做」；PRODUCT.md 是「最终产品长什么样」。

---

## 1. 三十秒上下文

我们在做 **Mauchat**（Flutter AI 聊天 App）的**本地推理 + UI 截图理解**能力，拆成三个仓库：

| 仓库 | 路径 | 今天状态 |
|------|------|----------|
| **local-infer-core** | `D:\repo\local-infer-core` | **Phase 1 完成**；Phase 2 FFI + dart 包已落地 |
| **ui-extractor** | `D:\repo\ui-extractor` | **可运行**：布局 + OCR + 图标匹配一体；ML 通过编译期动态链接 `infer_core.dll` |
| **Mauchat** | `D:\repo\mauchat` | **Phase 2 已接入**本地 OCR（`local_infer_core`）；E2E 待 Windows 验收 |

你的主战场是 **从零实现 local-infer-core**，然后 **瘦身 ui-extractor**，最后 **Mauchat 接 DLL**。

---

## 2. 必读文档（按顺序）

1. [local-infer-core/PRODUCT.md](PRODUCT.md) — manifest、包命名、EP 透传、LICENSE、Release
2. [ui-extractor/PRODUCT.md](../ui-extractor/PRODUCT.md) — 迁移后 ui-extractor 职责
3. [mauchat/PRODUCT.md](../mauchat/PRODUCT.md) — App 如何用两个 DLL
4. [ui-extractor/docs/architecture.md](../ui-extractor/docs/architecture.md) — **现状**流水线（迁移前参考）
5. [mauchat/docs/dev/思考/开发日志.md](../mauchat/docs/dev/思考/开发日志.md) — 6.22 前后：为何做 ui-extractor

---

## 3. 已拍板决策（不要重新争论）

|  topic | 决定 |
|--------|------|
| 推理格式 | 桌面 **ONNX (ORT)**，移动 **MNN** |
| NCNN | **弃用**，ui-extractor 里的 `backend-ncnn` / `ncnn-bind` 最终删除 |
| 模型耦合 | **manifest 驱动**；禁止硬编码 `pp-ocrv5_mobile_det.onnx` 这类文件名 |
| 包 id | `{kind}.{family}.{name}.{format}.{quant}`，例：`ocr.paddle.ppocr6-tiny.onnx.fp32` |
| OCR 版本 | 目标 **PP-OCRv6**（tiny / small / medium）；桌面 ONNX 可 wrap **oar-ocr ≥ 0.7** |
| 图标 Release | 只发 **`icons.bundled.v1.mobileclip2-s0.*`**（多库合并索引）；不单发 mdi/tabler |
| EP 策略 | **透传** `RuntimeConfig.execution_providers`；内核不擅自改链；缺省才 `auto` |
| 分发 | **GitHub Releases** 为主；zip 含 manifest + LICENSE + NOTICE |
| DLL | `infer_core.dll` 独立；ui-extractor 可链 rlib，Mauchat 走 FFI |

---

## 4. ui-extractor 今天有什么（迁移来源）

### 要迁到 local-infer-core 的

| 路径 | 内容 |
|------|------|
| `src/ocr/ort.rs` | Paddle OCR via oar-ocr（**先升 0.7+ 再迁 v6**） |
| `src/ocr/mod.rs` | `OcrConfig`、`OcrWord`、resize/scale 工具 |
| `src/icon/embedder_ort.rs` | MobileCLIP2 ONNX 嵌入 |
| `src/icon/preprocess.rs` | 256×256 预处理、L2 norm、`EMBED_DIM=512` |
| `src/icon/embedding.rs` | `embeddings.bin` 格式（magic `MCL2`，v1 f32 / v2 int8） |
| `src/icon/library.rs` / `pack.rs` | 索引加载、cosine 检索 |
| `src/ort_runtime.rs` | ORT EP 选择（**重写为透传版**，见 PRODUCT.md） |

### 留在 ui-extractor 的

| 路径 | 内容 |
|------|------|
| `src/layout/` | Canny、轮廓、UI 树（零 ML） |
| `src/pipeline.rs` | 布局 + OCR 并行、挂词、挂图标 |
| `src/engine.rs` | 有状态 `ExtractEngine`（改为注入 infer-core） |
| `src/annotate.rs` / `skeleton.rs` | 可视化 |
| `src/ffi.rs` + `dart/` | C ABI / Dart 包 |
| `tests/cases/` | Golden 回归 |

### 今天要删/废弃的方向

- `src/ocr/ncnn.rs`、`src/icon/embedder_ncnn.rs`、`crates/ncnn-bind/`
- `OcrConfig::det_model()` 里写死的 v5 文件名
- Release 脚本里的 ncnn 路径（`download_models_ncnn.ps1` 等）

### 图标源（建索引用，不单独 Release）

- `scripts/download_mdi_icons.ps1` — MDI
- `scripts/download_icon_libraries.ps1` — Tabler、Fluent UI、Font Awesome
- 产出合并进 `icons.bundled.v1.*` 的 `embeddings.bin`

---

## 5. Mauchat 今天有什么（集成触点）

| 文件 | 现状 | 目标 |
|------|------|------|
| `lib/services/transcription/image_transcription_service.dart` | 只调云端视觉 API | 增加 **infer-core 本地 OCR** 分支 |
| `lib/models/transcription/image_transcription.dart` | `ImageTranscriptionEntry.model(rowId)` | 增加 **`localPackId`** |
| `lib/config/app_config.dart` | `imageTranscriptionEntries` | 可配置本地 OCR pack |
| 浏览器 / 安卓自动化 | 实验性 ui-extractor | `ui_extractor.dll` + registry 配置 |
| 缓存 | `caches/text_transcript/` | 本地 OCR 与云端转写**共用 hash** |

Mauchat **不要**在 Dart 里重写 OCR/嵌入；只 FFI + 设置 UI + 下载 zip。

---

## 6. 目标仓库结构（local-infer-core）

```
local-infer-core/
├── IMPLEMENTATION.md          ← 本文
├── PRODUCT.md
├── crates/
│   ├── infer-core/            # rlib：registry, runtime, ocr, embed, icon_index
│   └── infer-core-ffi/        # cdylib → infer_core.dll / libinfer_core.so
├── dart/                      # pub 包 local_infer_core（见 §6.1）
│   ├── pubspec.yaml
│   ├── hook/build.dart        # Native Assets：仅 infer_core 动态库
│   └── lib/
├── schema/
│   └── manifest.v1.json       # JSON Schema
└── tools/
    ├── pack/                  # 打 zip、写 manifest、复制 LICENSE/NOTICE
    ├── quant/                 # ONNX/MNN 量化（后期）
    └── icon-index/            # 从 ui-extractor icon build 逻辑迁入或调用
```

### 6.1 Dart 包 `local_infer_core`（本仓库 `dart/`）

**Mauchat 接本地 OCR / 模型管理 / RuntimeConfig 透传，主要靠这个包。** 不是 ui-extractor 的一部分。

| 项 | 说明 |
|----|------|
| pub 名 | `local_infer_core`（path: `../local-infer-core/dart` 或将来 pub.dev） |
| Native Assets hook | 从 **local-infer-core** GitHub Release 拉 `infer_core-{platform}.zip`，**只含 DLL/so**，不含模型权重 |
| 模型包 | **不在 hook 里捆绑**；首次启动解压默认 pack 到 `{app_data}/models/`，或按需 `downloadPack()` |

#### 对外 Dart API（目标）

```dart
// 运行时 / EP 透传
final registry = await LocalInferRegistry.open(
  modelsDir: appModelsDir,
  runtimeConfig: RuntimeConfig(onnx: OnnxConfig(eps: ['auto'])),
);

// 跨模态转写
final ocr = registry.ocr('ocr.paddle.ppocr6-tiny.onnx.fp32');
final text = await ocr.plainText(imageBytes);

// 嵌入 / 图标索引（ui-extractor 也可直接用；Mauchat 若只做 OCR 可不碰）
final embed = registry.embed('embed.mobileclip2-s0.onnx.fp32');
final index = registry.iconIndex('icons.bundled.v1.mobileclip2-s0.int8');

// 模型管理
await ModelCatalog.installPack('ocr.paddle.ppocr6-small.onnx.fp32'); // 下载 zip → 校验 sha256 → 解压
PackLicense.readNotice(packId);
```

#### hook/build.dart 原则

- Release 资产名示例：`infer-core-windows-x64.zip` → `infer_core.dll`
- Android：`libinfer_core.so`
- **不要**再像 ui-extractor 旧 hook 那样把 `models/`、`embeddings.bin` 打进 Native Assets（体积、许可、升级都不合适）
- 默认 pack 由 **Mauchat 首次启动** 或 **ModelCatalog.ensureDefaults()** 解压到可写目录

#### catalog.json（Dart 侧，随 App 或 remote 更新）

```json
{
  "packs": [
    {
      "id": "ocr.paddle.ppocr6-tiny.onnx.fp32",
      "urls": ["https://github.com/.../....zip"],
      "sha256": "...",
      "size_bytes": 8500000
    }
  ]
}
```

与 Rust `registry` 共用同一 `{models_dir}/{pack_id}/` 布局。

### 6.2 Dart 包 `ui_extractor`（ui-extractor 仓库 `dart/`）

**只做 UI JSON 提取**；依赖 `local_infer_core` 共享 `modelsDir`、`RuntimeConfig`、pack id 类型。

| 项 | 说明 |
|----|------|
| pub 名 | `ui_extractor`（已有） |
| 依赖 | `local_infer_core: ^x.y.z`（path 或 pub.dev） |
| Native Assets hook | 只拉 `ui_extractor.dll` / `libui_extractor.so` |
| 运行时 | `ui_extractor` 动态库在 Rust 侧链接/加载 `infer_core` — **Mauchat 需同时部署两个 so/dll**（hook 各注册各的 asset，或 ui_extractor hook 声明依赖 infer_core 并打包两份） |

```dart
final ui = UiExtractorEngine.create(
  modelsDir: registry.modelsDir,           // 与 local_infer_core 同一目录
  runtimeConfig: registry.runtimeConfig,   // EP 透传一次即可
  ocrPackId: 'ocr.paddle.ppocr6-tiny.mnn.fp32',
  iconIndexPackId: 'icons.bundled.v1.mobileclip2-s0.int8',
);
final json = ui.extractBytes(screenshotBytes);
```

#### 迁移 ui-extractor 现有 `dart/`

| 现有 | 迁移后 |
|------|--------|
| `ExtractorConfig` 硬编码模型路径 | pack id + `modelsDir`，与 manifest 对齐 |
| `BundledAssets` 找 hook 里的 models/ | 删除；改 `local_infer_core` 的 `modelsDir` |
| hook 下载含 models 的 fat zip | hook **仅** native 库；模型走 ModelCatalog |

### 6.3 Mauchat `pubspec.yaml`

```yaml
dependencies:
  local_infer_core:
    path: ../local-infer-core/dart   # 或 git / pub.dev
  ui_extractor:
    path: ../ui-extractor/dart       # 仅 UI 自动化模块需要
```

| 功能 | 需要的包 |
|------|----------|
| 跨模态转写（本地 OCR） | `local_infer_core` |
| 浏览器 / 安卓 UI 自动化 | `local_infer_core` + `ui_extractor` |
| 仅云端视觉转写 | 都不需要 |

### 6.4 版本对齐

- Git tag `local-infer-core/v0.3.0` ↔ dart `0.3.0` ↔ Release 里 `infer_core` zip + 模型 pack zips
- `ui_extractor` dart 版本依赖 `local_infer_core: ^0.3.0`，native `ui_extractor.dll` 与 `infer_core.dll` **同 tag 构建**

### infer-core 最小公开 API（Phase 1 结束前要有）

```rust
RuntimeConfig::from_json(...) / from_env_or_default()
Registry::open(models_dir, runtime_config)
registry.load_ocr(pack_id) -> OcrEngine
registry.load_embed(pack_id) -> EmbedEngine
registry.load_icon_index(pack_id) -> IconIndex

ocr.plain_text(&image) -> String
ocr.recognize(&image) -> Vec<OcrWord>
embed.embed_rgb256(...) -> Vec<f32>
icon_index.match_embedding(...) -> Option<IconMatch>
```

### FFI（Phase 2）

- `infer_registry_create(base_dir, runtime_config_json)`
- `infer_ocr_plain_text` / `infer_ocr_recognize_bytes`
- `infer_embed_*` / `infer_icon_index_*`
- `infer_string_free`

---

## 7. 实施顺序（按 PR 切）

### Phase 0 — 契约与空壳（本仓库可独立 merge）

- [ ] `schema/manifest.v1.json`
- [ ] `infer-core`: 解析 manifest、`license.files` 校验、扫描 `{models_dir}/{pack_id}/`
- [ ] `RuntimeConfig` + EP 透传骨架（可先只实现 `cpu` + Windows `directml`）
- [ ] `tools/pack` 模板：生成带 LICENSE/NOTICE 的空包目录
- [ ] 单测：缺 LICENSE 的包被拒绝

### Phase 1 — ONNX 推理

- [ ] 从 ui-extractor 迁入 OCR（oar-ocr **0.7+**，v6 tiny + v6 detection config）
- [ ] 迁入 MobileCLIP2 embed + `EmbeddingIndex`（MCL2）
- [ ] 官方样例包目录（可先不 Release）：`ocr.paddle.ppocr6-tiny.onnx.fp32`、`embed.mobileclip2-s0.onnx.fp32`
- [ ] 删除 ui-extractor 内 ORT OCR/embed 的**重复实现**改为 `path` 依赖 infer-core（ui-extractor PR）

### Phase 2 — FFI + Mauchat 本地 OCR

- [x] `infer-core-ffi` + **`dart/` 包 `local_infer_core`**（hook + Registry + OcrEngine）
- [x] `ModelCatalog` + 默认 pack 首次解压（fixture / bundled / env 回退）
- [x] Mauchat：`ImageTranscriptionEntry.localPackId` + `plain_text` 转写
- [ ] 设置：OCR pack 选择；推理设备 → `RuntimeConfig` JSON 透传 EP（pack 选择 UI 待扩展）

### Phase 3 — MNN + Android

- [ ] MNN runtime + Paddle det/rec adapter（**不能**指望 oar-ocr）
- [ ] MNN embed int8 + OCR fp32 包 + Android CI
- [ ] Mauchat 内置 assets 解压到 `{app_data}/models/`

### Phase 4 — Release 流水线

- [ ] GitHub Actions：打 zip + SHA256 + Release notes（SPDX 摘要）
- [ ] `icons.bundled.v1.*`：合并 mdi/tabler/fluent/fa 建索引 + NOTICE 分项
- [ ] Mauchat catalog：`pack_id` → URL 列表 + sha256

### Phase 5 — 收尾

- [ ] ui-extractor 删 ncnn、更新 docs/getting-started
- [ ] Mauchat UI 提取路径接 registry
- [ ] 用户 custom 图标包导入 + LICENSE 强制

---

## 8. manifest / LICENSE 检查清单

每个官方 zip **必须**包含：

```
{pack_id}/
├── manifest.json    # 含 license.spdx, license.files, license.upstream
├── LICENSE
├── NOTICE           # 多上游或 spdx: SEE NOTICE 时必需
└── （权重或 embeddings.bin）
```

`tools/pack` CI：**缺文件 = exit 1**。  
`icons.bundled` 的 NOTICE 必须分项列出 MDI / Tabler / Fluent / FA（见 PRODUCT.md 示例）。

---

## 9. 验证标准（Definition of Done）

### infer-core

- `cargo test` 通过 manifest 解析、license 校验、MCL2 roundtrip
- 样例图 OCR plain_text 非空（v6 tiny）
- 样例 icon crop cosine 匹配有合理 hit
- `LOCAL_INFER_ORT_EP=cpu` 与 `directml,cpu` 均可跑通

### ui-extractor（迁移后）

- `ui-extractor extract --models-dir ...` 与迁移前 golden cases **等价或更好**
- 不再 `depend` oar-ocr / ort（仅 depend infer-core）
- `cargo build` 无 ncnn feature

### Mauchat

- 无 vision 模型发图 → 本地 OCR 转写 → 写入 `text_transcript` 缓存
- 设置可切换 OCR pack（至少 tiny vs small 测一条）
- 关于页/模型管理可打开 LICENSE

---

## 10. 常见误区（别踩）

1. **在 ui-extractor 里继续堆 ML** — 新推理逻辑只进 infer-core  
2. **保留 NCNN「顺便支持」** — 已否决，移动只有 MNN  
3. **硬编码模型文件名** — 只认 manifest  
4. **EP 在 infer-core 里写死 DirectML** — 必须透传 RuntimeConfig  
5. **单独 Release icons.mdi.*** — 只 Release `icons.bundled.v1.*`  
6. **Release zip 不带 LICENSE** — CI 应失败  
7. **Mauchat 用 Dart 调 oar-ocr** — 只 FFI `local_infer_core` → `infer_core.dll`  
8. **以为 oar-ocr 0.6.3 能跑 v6** — 必须 ≥ 0.7  
9. **在 ui_extractor hook 里捆绑 models/** — 模型包走 `ModelCatalog`，hook 只带 DLL  
10. **一个 Dart 包包打天下** — OCR 用 `local_infer_core`，UI 树用 `ui_extractor`，职责分开

---

## 11. 参考链接

- oar-ocr PP-OCRv6：<https://github.com/GreatV/oar-ocr>（v0.7.0+）
- Paddle 官方 v6 ONNX：<https://github.com/GreatV/oar-ocr/blob/main/docs/models.md>
- ui-extractor 图标文档：`ui-extractor/docs/dev/icon-matching.md`、`mdi-icons.md`

---

## 12. 第一个 PR 建议

**最小可合并单元：**

1. 初始化 `cargo workspace`（infer-core + infer-core-ffi 空 crate）
2. `schema/manifest.v1.json` + manifest 解析 + license 文件存在性校验
3. 一个 fixture 包目录在 `crates/infer-core/tests/fixtures/ocr.paddle.ppocr6-tiny.onnx.fp32/`（可无真实 onnx，先测 manifest/license）
4. README 指向 IMPLEMENTATION.md

不要第一个 PR 就接 MNN 或 Mauchat Flutter。
