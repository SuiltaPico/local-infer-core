# local-infer-core — 产品目标

**local-infer-core** 是 Mauchat 生态的通用本地推理内核：模型无关、manifest 驱动、即插即用。独立产出动态库（`infer_core.dll` / `libinfer_core.so`），供 **Mauchat** 与 **ui-extractor** 共用。

相关仓库：

- [ui-extractor](../ui-extractor/PRODUCT.md) — UI 截图 → JSON 树（依赖本仓库）
- [Mauchat](../mauchat/PRODUCT.md) — 消费方 App

---

## 定位

| 做什么 | 不做什么 |
|--------|----------|
| OCR（Paddle 等 family adapter） | UI 布局、轮廓检测 |
| 图片嵌入（MobileCLIP2 等） | 图标索引构建的业务 UI |
| 模型包扫描、加载、推理 | 云端 LLM 调用 |
| C ABI / Dart FFI 友好 DLL | Flutter UI |

一句话：**「模型操作系统」** — 有 manifest、格式对、就能跑。

---

## 推理后端

| 平台 | 格式 | 运行时 |
|------|------|--------|
| Windows / Linux / macOS（桌面） | ONNX | ONNX Runtime |
| Android / 移动端 | MNN | MNN |

**不使用 NCNN。**

### ONNX Execution Provider（透传）

**infer-core 不替消费方「猜设备」** — EP 链由上游传入，内核负责校验、挂载 ORT Session，并按需探测 `is_available()`。

消费方（Mauchat、ui-extractor、CLI）通过 **`RuntimeConfig`** 传入；未指定时内核使用 `auto` 预设（见下）。

#### RuntimeConfig（概念）

```json
{
  "onnx": {
    "execution_providers": ["directml", "cpu"],
    "intra_threads": 4,
    "inter_threads": 1
  }
}
```

| 字段 | 说明 |
|------|------|
| `execution_providers` | EP 名称有序列表，**按顺序**交给 ORT（与 ORT API 一致） |
| `intra_threads` / `inter_threads` | 可选；纯 CPU 时由消费方或 `auto` 预设填充 |

Rust / FFI 等价：`RuntimeConfig { onnx: Some(OnnxConfig { eps: vec![...] }) }`。

#### 透传路径（优先级从高到低）

1. **显式 API** — `infer_registry_create(base_dir, runtime_config_json)` / `EngineBuilder::runtime_config(...)`
2. **环境变量** — `LOCAL_INFER_ORT_EP=cpu,directml`（逗号分隔链；仅当 API 未传时使用）
3. **`auto` 预设** — 均未指定时，内核按平台生成建议链（可文档化，非强制）

#### 支持的 EP 名称（透传值）

| 名称 | 平台 | compile feature |
|------|------|-----------------|
| `cpu` | 全平台 | 始终可用 |
| `directml` | Windows | `ort-directml` |
| `coreml` | macOS | `ort-coreml` |
| `cuda` | Linux / Windows | `ort-cuda` |

消费方传什么，内核就尝试挂什么；某项 `is_available()` 为 false 时 **跳过并记录日志**，不 silently 改链（除非消费方在 config 里显式开启 `fallback: true`，见下）。

#### `auto` 预设（仅 `execution_providers` 缺省或含 `"auto"` 时展开）

| 平台 | 默认链 |
|------|--------|
| Windows | `directml` → `cpu` |
| macOS | `coreml` → `cpu` |
| Linux | `cuda` → `cpu`（未编 CUDA 时仅 `cpu`） |

#### 可选行为（消费方控制，内核不擅自决定）

| 选项 | 默认 | 说明 |
|------|------|------|
| `append_cpu_fallback` | `true` | 链末无 `cpu` 时自动追加（ORT 惯例） |
| `gpu_single_session` | `true` | 链首为 GPU 类 EP 时，建议单 Session；供 icon 批处理等上游读此 hint |

manifest 可含 **`runtime_hint`**（非强制），消费方可忽略：

```json
"runtime_hint": { "ep": ["cpu"], "reason": "tiny model, cpu_ok" }
```

#### 示例

```bash
# Mauchat 设置「省电」→ 传 ["cpu"]
# Mauchat 设置「自动」→ 传 ["auto"] 或省略
# 高级用户 / 脚本
LOCAL_INFER_ORT_EP=cuda,cpu ui-extractor extract ...
```

**MNN 后端**无 ORT EP 概念；对应字段为 `mnn` 段（如 `precision`、`num_thread`、`backend: cpu|opencl|vulkan`），同样透传，规则平行。

---

## 模型包契约

每个模型包目录名 = 包 id，形如：

```
{kind}.{family}.{name}.{format}.{quant}
```

示例：

```
ocr.paddle.ppocr6-tiny.onnx.int8
ocr.paddle.ppocr6-small.mnn.fp32
embed.mobileclip2-s0.onnx.int8
icons.bundled.v1.mobileclip2-s0.int8    # 预计算嵌入索引（官方 Release 仅此一种）
```

### manifest.json（schema v1）

包内必须含 `manifest.json`，代码**只读 manifest**，不认硬编码文件名。

**每个可 Release / 可导入的包还必须带许可证文件**（见下节 [许可证与归属](#许可证与归属)）；`registry` 加载时校验，缺则拒绝启用（仅 `warn` 的调试模式除外）。

**OCR 包（family: `paddle`）**

```json
{
  "schema": 1,
  "id": "ocr.paddle.ppocr6-tiny.onnx.int8",
  "kind": "ocr",
  "family": "paddle",
  "version": 6,
  "format": "onnx",
  "quant": "int8",
  "files": { "det": "det.onnx", "rec": "rec.onnx", "dict": "ppocrv6_tiny_dict.txt" },
  "runtime": "onnxruntime",
  "inputs": { "det_max_side": 960, "rec_height": 48 },
  "detection": { "score_threshold": 0.2, "box_threshold": 0.45, "unclip_ratio": 1.4 },
  "license": {
    "spdx": "Apache-2.0",
    "files": ["LICENSE", "NOTICE"],
    "upstream": {
      "name": "PaddleOCR / PP-OCRv6",
      "url": "https://github.com/PaddlePaddle/PaddleOCR",
      "version": "PP-OCRv6_tiny"
    }
  }
}
```

**嵌入包（family: `mobileclip2`）**

```json
{
  "schema": 1,
  "id": "embed.mobileclip2-s0.mnn.int8",
  "kind": "embed",
  "family": "mobileclip2",
  "format": "mnn",
  "quant": "int8",
  "files": { "vision": "vision.mnn" },
  "dim": 512,
  "preprocess": { "input_size": 256, "layout": "NCHW", "normalize": "mobileclip2" },
  "license": {
    "spdx": "SEE LICENSE",
    "files": ["LICENSE", "NOTICE"],
    "upstream": {
      "name": "MobileCLIP2-S0",
      "url": "https://github.com/apple/ml-mobileclip",
      "component": "vision encoder weights (converted)"
    }
  }
}
```

**图标索引包（kind: `icon_index`）**

开发与建索引阶段可拉取多套开源图标（MDI、Tabler、Fluent UI、Font Awesome 等，见 ui-extractor `assets/svg/`）。**官方 Release 只发布一种经我们筛选合并的嵌入包** `icons.bundled.v1.*`，不逐库分别 Release。

```json
{
  "schema": 1,
  "id": "icons.bundled.v1.mobileclip2-s0.int8",
  "kind": "icon_index",
  "embed_model_id": "embed.mobileclip2-s0.mnn.int8",
  "files": { "index": "embeddings.bin" },
  "namespaces": ["mdi", "tabler", "fluent", "fa"],
  "count": 12000,
  "index_format": "mcl2-v2",
  "license": {
    "spdx": "SEE NOTICE",
    "files": ["LICENSE", "NOTICE"],
    "upstream": [
      { "name": "Material Design Icons", "spdx": "Apache-2.0", "url": "https://github.com/Templarian/MaterialDesign-SVG" },
      { "name": "Tabler Icons", "spdx": "MIT", "url": "https://github.com/tabler/tabler-icons" },
      { "name": "Fluent UI System Icons", "spdx": "MIT", "url": "https://github.com/microsoft/fluentui-system-icons" },
      { "name": "Font Awesome Free", "spdx": "SEE NOTICE", "url": "https://fontawesome.com/license/free" }
    ]
  }
}
```

条目标识仍带 namespace 前缀（如 `mdi:cog`、`tabler:home`），便于 LLM 理解与用户自定义库区分。

索引包的 `embed_model_id` 必须与运行时加载的嵌入模型在 **family、dim、preprocess** 上一致。

### 许可证与归属

模型包分发权重或衍生索引，**必须可审计、可再分发**。避免侵权靠流程，不靠口头约定。

#### 包内必备文件

| 文件 | 何时必需 | 内容 |
|------|----------|------|
| `LICENSE` | 始终 | 本包**整体**对外许可声明；单一 SPDX 时写完整许可证文本或 `Apache-2.0` 全文 |
| `NOTICE` | 多上游 / `spdx: SEE NOTICE` | 各组件版权、许可证摘要、修改说明（ONNX/MNN 转换、量化、int8 索引等） |
| `manifest.json` → `license` | 始终 | 机器可读：`spdx`、`files[]`、`upstream` |

zip / 目录结构示例：

```
ocr.paddle.ppocr6-tiny.onnx.int8/
├── manifest.json
├── LICENSE
├── NOTICE
├── det.onnx
├── rec.onnx
└── ppocrv6_tiny_dict.txt
```

#### manifest.`license` 字段

| 字段 | 说明 |
|------|------|
| `spdx` | 单一许可证用 SPDX id（如 `Apache-2.0`、`MIT`）；混合来源用 `SEE NOTICE` |
| `files` | 相对包根的路径，至少含 `LICENSE`；多组件时含 `NOTICE` |
| `upstream` | 对象或数组：原始项目名、URL、版本/组件、可选 `spdx` |

`registry` / `tools/pack` **CI 校验**：

- `license.files` 所列文件均存在且非空  
- `upstream` 非空  
- 官方 Release zip 缺任一项 → **构建失败**

#### 官方包参考（打包时写入 NOTICE，非法律意见）

| 包 kind | 上游 | 常见许可证 |
|---------|------|------------|
| OCR / Paddle | [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | Apache-2.0 |
| embed / MobileCLIP2 | [apple/ml-mobileclip](https://github.com/apple/ml-mobileclip) | 以仓库 LICENSE 为准，NOTICE 中引用 |
| icon_index / bundled | MDI、Tabler、Fluent、FA 等 | 各库不同 → **必须** `NOTICE` 分项列出 |

转换（ONNX→MNN、量化）不改变许可证义务；NOTICE 中注明「未改模型语义，仅格式/精度转换」。

#### 用户自定义包

用户导入的 `icons.custom.*` / 第三方 OCR 包：

- 同样必须带 `license` + `LICENSE`（`tools/pack` 导入向导可强制填写）  
- Mauchat **不托管、不担保** 用户包版权；设置页展示 manifest 中的 `license` 供用户自查  
- App 内置 catalog 只签名/哈希**官方** Release 包

#### Mauchat / App 侧

- 设置 → 模型管理：每个已安装包可查看 `LICENSE` / `NOTICE`  
- App 关于页 / 开源声明：聚合已启用官方包的 NOTICE（不自动包含用户 custom 包）  
- `.mauchat.bak` 备份 custom 包时 **一并备份** 其 LICENSE 文件

---

## 目录布局

默认模型根目录 `{LOCAL_INFER_ROOT}`（Mauchat 为 app 数据目录；CLI 可用 `--models-dir` 或环境变量）：

```
{LOCAL_INFER_ROOT}/
├── registry.json                 # 可选：已启用包、优先级
├── ocr.paddle.ppocr6-tiny.onnx.int8/
│   ├── manifest.json
│   ├── LICENSE
│   ├── NOTICE
│   └── …
├── embed.mobileclip2-s0.onnx.int8/
└── icons.bundled.v1.mobileclip2-s0.int8/
```

解析顺序：显式路径 → `LOCAL_INFER_ROOT` → App 内置 assets（首次解压）。

---

## 仓库结构（目标）

```
local-infer-core/
├── crates/infer-core/           # Rust 库：registry、runtime、OCR/embed adapter
├── crates/infer-core-ffi/       # cdylib → infer_core.dll / .so
├── schema/manifest.v1.json      # JSON Schema，CI 校验
└── tools/
    ├── pack/                    # 打 Release zip
    ├── quant/                   # ONNX/MNN 量化
    └── icon-index/              # PNG → embeddings.bin
```

### 对外 API（概念）

**Rust**

```rust
let cfg = RuntimeConfig::from_env_or_default()?;
let registry = Registry::open(models_dir, cfg)?;

let ocr = registry.load_ocr("ocr.paddle.ppocr6-tiny.mnn.int8")?;
ocr.plain_text(&image)?;                    // Mauchat 跨模态转写
ocr.recognize(&image)? -> Vec<OcrWord>;     // ui-extractor 挂词

embed.embed_rgb256(&crop)? -> Vec<f32>;
icon_index.match_embedding(&vec)?;
```

**C FFI（Mauchat Dart）**

- `infer_registry_create(base_dir, runtime_config_json)` — **EP 在此透传**
- `infer_registry_load_pack`
- `infer_ocr_recognize_bytes` / `infer_ocr_plain_text`
- `infer_embed_*` / `infer_icon_index_*`

**Dart 包 `local_infer_core`（本仓库 `dart/`）**

- Native Assets hook：仅 `infer_core.dll` / `libinfer_core.so`（**不含**模型 zip）
- 封装上述 FFI + `ModelCatalog`（下载/解压/校验 pack）+ `RuntimeConfig` 类型
- Mauchat 跨模态转写 **只依赖此包**；UI 自动化另加 [ui_extractor](../ui-extractor/PRODUCT.md) dart 包

详见 [IMPLEMENTATION.md §6.1](IMPLEMENTATION.md#61-dart-包-local_infer_core本仓库-dart)。

---

## 官方 Release（GitHub Releases）

CI 自动发布 zip，供下载解压到 `{LOCAL_INFER_ROOT}`。

### 神经网络包

| 包 id | 说明 |
|-------|------|
| `ocr.paddle.ppocr6-tiny.onnx.fp32` | 默认内置，聊天截图 OCR（已足够小，不做 int8） |
| `ocr.paddle.ppocr6-small.onnx.fp32` | 可选升级 |
| `ocr.paddle.ppocr6-medium.onnx.fp32` | 可选升级 |
| `embed.mobileclip2-s0.onnx.int8` | 默认内置，图标嵌入（**OCR 以外唯一官方 int8 包**） |
| `embed.mobileclip2-s0.onnx.fp32` | 精度优先 |

每个 zip：`manifest.json` + `LICENSE`（+ 多上游时 `NOTICE`）+ 权重 + 字典（OCR）。Release notes 附 SPDX / 上游链接摘要。

### 图标嵌入包

开发与 CI 可从多套开源 SVG 离线合建索引；**对外 Release 仅一种官方精选包**：

| 包 id | 说明 |
|-------|------|
| `icons.bundled.v1.mobileclip2-s0.int8` | 常见开源图标（MDI / Tabler / Fluent / FA 等合并），离线建索引，**默认内置** |
| `icons.bundled.v1.mobileclip2-s0.fp32` | 同上 fp32 版（可选） |

不逐库 Release（如单独的 `icons.mdi.*`）；用户自定义场景走 `icons.custom.{id}.*`。

桌面 ONNX 路径可 wrap [oar-ocr](https://github.com/GreatV/oar-ocr)（≥ 0.7 支持 PP-OCRv6）；MNN 路径在 infer-core 内自实现 Paddle det/rec adapter。

---

## 实施阶段

| 阶段 | 内容 |
|------|------|
| 0 | manifest schema + registry 扫描 + **license 校验** |
| 1 | infer-core：ONNX OCR + ONNX embed |
| 2 | infer-core-ffi + Mauchat 本地 OCR |
| 3 | MNN runtime + Android 包 + Release 流水线 |
| 4 | ui-extractor 迁入依赖 infer-core |
| 5 | 模型 CDN / 用户自定义图标库导入 |

---

## 非目标

- 通用任意 ONNX 图推理（只做 OCR、embed 等有 adapter 的 family）
- 训练 / 微调
- 替代云端多模态大模型（仅轻量离线兜底）
