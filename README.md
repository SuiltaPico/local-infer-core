# local-infer-core
本地推理内核：OCR、图片嵌入、图标索引，采用 manifest 驱动；桌面侧主打 ONNX（ORT），移动侧支持 MNN。

## Clone 后先做什么
在仓库根目录按顺序执行（PowerShell）：

```powershell
# 1) 进入仓库
cd D:\repo\local-infer-core

# 2) 拉取 MNN 源码/Android 预编译库（workspace 的 mnn-sys 需要）
powershell -ExecutionPolicy Bypass -File .\scripts\download_mnn_android.ps1

# 3) 基础编译检查（推荐先跑）
cargo check

# 4) Python 虚拟环境 + MNN 转换器（download_all_packs 转 MNN 包时需要 mnnconvert）
python -m venv .env
.\.env\Scripts\Activate.ps1
python -m pip install -U pip
pip install -r requirements.txt

# 5) 下载示例模型包（便于本地验证 OCR / embed）
powershell -ExecutionPolicy Bypass -File .\scripts\download_all_packs.ps1
```

如果你只想先验证核心 ONNX 路径（不关心 workspace 里 `mnn-sys`），可以用：

```powershell
cargo check -p infer-core -p infer-core-ffi
```

## 新人联调验收（从 clone 到可用）

如果你要验证 `ui-extractor` 端到端可用，推荐按这个最短链路：

```powershell
# 0) 仓库布局（建议）
# D:\repo\local-infer-core
# D:\repo\ui-extractor

# 1) 在 local-infer-core 构建 infer_core.dll
cd D:\repo\local-infer-core
cargo build -p infer-core-ffi

# 2) 到 ui-extractor 安装模型包
cd D:\repo\ui-extractor
powershell -ExecutionPolicy Bypass -File .\scripts\install_packs.ps1 -Platform windows

# 3) 复制 infer_core.dll 给 ui-extractor CLI
Copy-Item -Force ..\local-infer-core\target\debug\infer_core.dll .\target\debug\infer_core.dll

# 4) 跑一条真实命令（布局 + OCR + 图标）
cargo run --bin ui-extractor -- extract --input .\tests\cases\zhihu\input.png --annotate `
  --models-dir .\models `
  --ocr-pack ocr.paddle.ppocr6-tiny.onnx.fp32 `
  --icon-index-pack icons.bundled.v1.mobileclip2-s0.int8
```

出现 `0xc0000135` / `STATUS_DLL_NOT_FOUND` 时，优先检查第 3 步是否完成。

## 常用开发命令

```powershell
# 全量检查
cargo check

# 运行测试
cargo test

# 只测核心库
cargo test -p infer-core -p infer-core-ffi
```

## 脚本地图

### 1) 日常开发最常用

| 目标 | 脚本 |
|------|------|
| 准备 MNN 源码与 Android 预编译库（首次 clone 建议先跑） | `scripts/download_mnn_android.ps1` |
| 下载全部示例模型包（OCR + embed） | `scripts/download_all_packs.ps1` |
| 下载图标 SVG 并栅格化 PNG（icons.bundled 建索引用） | `scripts/download_icons.ps1 -Rasterize` |
| 构建 icons.bundled 索引包 | `tools/icon-index/build_bundled.ps1` |
| 仅下载 OCR 示例包（PP-OCRv6） | `scripts/download_ppocr6_all.ps1` 或 `scripts/download_ppocr6_pack.ps1` |
| 仅下载 embed 示例包（MobileCLIP2） | `scripts/download_embed_all.ps1` 或 `scripts/download_embed_mobileclip2_pack.ps1` |
| 下载最小 OCR fixture（轻量测试） | `scripts/download_ppocr6_tiny_fixture.ps1` |

### 2) 构建 MNN 模型包（ONNX -> MNN）

| 目标 | 脚本 |
|------|------|
| 构建全部 embed MNN 包 | `scripts/build_embed_mnn_all.ps1` |
| 构建指定 embed MNN 包 | `scripts/build_embed_mnn_pack.ps1` |
| 构建全部 PP-OCRv6 MNN 包 | `scripts/build_ppocr6_mnn_all.ps1` |
| 构建指定 PP-OCRv6 MNN 包 | `scripts/build_ppocr6_mnn_pack.ps1` |
| 一次构建所有 MNN 包（聚合入口） | `scripts/build_all_mnn_packs.ps1` |

### 3) Android / 发布相关

| 目标 | 脚本 |
|------|------|
| 本地构建 Android 产物 | `scripts/build_android.ps1` |
| 构建 Android x86_64（单独流程） | `scripts/build_mnn_android_x86_64.ps1` |
| 打 Android release 包 | `scripts/build_release_android.ps1` |
| 打 Windows release 包 | `scripts/build_release_windows.ps1` |
| 校验 Windows release 包 | `scripts/test_release_windows.ps1` |

### 4) 其它辅助脚本

| 脚本 | 作用 |
|------|------|
| `scripts/cargo_retry.ps1` | 给其他脚本复用的重试/容错工具函数 |
| `scripts/patch_mnn_sys.ps1` | 当前为 no-op（已改为 workspace 内 vendored `mnn-sys`） |
| `scripts/packs/*.ps1` | pack 相关底层工具（供上层脚本调用） |

> 建议顺序（新环境）：`download_mnn_android.ps1` -> `cargo check` -> `.env` + `pip install -r requirements.txt` -> `download_all_packs.ps1`。  
> 图标索引包需要 **Node.js + npm**（`download_icons.ps1` 拉 SVG）和 **Rust**（`infer-core-helper icon rasterize-svg` 栅格化 PNG）。

## 仓库结构（最常用）

- `crates/infer-core`：核心能力（registry/runtime/ocr/embed/icon_index）
- `crates/infer-core-ffi`：C ABI 动态库（`infer_core.dll` / `libinfer_core.so`）
- `crates/mnn-sys`：MNN 绑定与构建桥接
- `scripts/`：模型下载、MNN 构建、发布脚本

## 文档入口

| 文档 | 用途 |
|------|------|
| [docs/dev/PRODUCT.md](docs/dev/PRODUCT.md) | 产品目标、对外契约、包规范 |

相关项目：[ui-extractor](../ui-extractor/PRODUCT.md)
