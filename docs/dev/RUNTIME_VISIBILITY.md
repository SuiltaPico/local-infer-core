# 推理后端可见性（Runtime Visibility）

本文档描述 **local-infer-core 已提供** 的运行时后端查询能力，以及 **宿主 App（如 Mauchat）后续接入时** 应改动的位置与预期 UI 行为。

> 设计原则：后端探测逻辑全部在 native / Dart 包内完成；宿主只负责传 `RuntimeConfig`、展示 JSON 字段。

## 1. 三个层次的后端信息

| 层次 | 含义 | 数据来源 | 何时可用 |
|------|------|----------|----------|
| **可用** | 当前 build + 设备上探测到的后端/EP | `infer_runtime_backends_json` / `tryLoadStatus` | App 启动后、打开设置页前 |
| **配置/解析** | 用户选项 + `"auto"` 解析结果 | `infer_runtime_status_json(config)` → `resolved_mnn_backend` / `resolved_eps` | 传入 `RuntimeConfig` 后 |
| **实际** | MNN Session 真正使用的 forward type | OCR `timings.mnn_session_backends` | 至少跑过一次 OCR（模型 init 后） |

### MNN forward type 名称对照

| 代码 | 名称 | 说明 |
|------|------|------|
| 0 | `cpu` | CPU |
| 3 | `opencl` | OpenCL GPU |
| 7 | `vulkan` | Vulkan GPU |
| 13 | `cpu_extension` | CPU 扩展路径（fp16/NEON 等），**仍是 CPU 族** |
| 4 | `auto` | MNN 自动选择（少见出现在 BACKENDS 结果） |

若 `resolved_mnn_backend == "vulkan"` 但 `mnn_session_backends == ["cpu"]` 或 `["cpu_extension"]`，表示 **GPU 创建失败已回退 CPU**。

## 2. 已实现的 API

### 2.1 FFI：`infer_runtime_status_json`

```c
int infer_runtime_status_json(
    const char* runtime_config_json,
    char** out_json
);
```

响应示例（Android / MNN build）：

```json
{
  "backend": "mnn",
  "available": ["cpu", "opencl", "vulkan"],
  "configured": {
    "mnn": { "backend": "vulkan", "precision": "normal" }
  },
  "resolved_mnn_backend": "vulkan",
  "resolved_eps": null
}
```

Windows / ORT build 示例：

```json
{
  "backend": "onnx",
  "available": ["cpu", "directml"],
  "configured": {
    "onnx": { "execution_providers": ["auto"], "append_cpu_fallback": true }
  },
  "resolved_mnn_backend": null,
  "resolved_eps": ["directml", "cpu"]
}
```

旧库无此符号时，Dart 层 `RuntimeCapabilities.tryLoadStatus` 会回退到 `infer_runtime_backends_json`（仅 `backend` + `available`）。

### 2.2 OCR timings 扩展字段

`infer_ocr_recognize_timed` 返回 JSON 的 `timings` 段：

```json
{
  "init_ms": 8.0,
  "predict_ms": 240.0,
  "mnn_configured_backend": "vulkan",
  "mnn_session_backends": ["vulkan"]
}
```

- `mnn_configured_backend`：仅 MNN build 有值；ORT build 为 `null`/省略。
- `mnn_session_backends`：det 模型 session 的 `getSessionInfo(BACKENDS)`；init 缓存命中时仍反映当前 session。
- 主后端：取 `mnn_session_backends[0]`（Dart：`OcrTimings.primaryMnnSessionBackend`）。

### 2.3 Dart 便捷 API

| API | 用途 |
|-----|------|
| `RuntimeCapabilities.tryLoadStatus(RuntimeConfig)` | 设置页 / benchmark 开头展示「配置后端」 |
| `RuntimeConfig.resolvedMnnBackend(available)` | 无新 FFI 时的纯 Dart 回退 |
| `OcrTimings.mnnConfiguredBackend` | OCR 结果中的配置后端 |
| `OcrTimings.mnnSessionBackends` | OCR 结果中的实际后端列表 |
| `OcrTimings.primaryMnnSessionBackend` | 实际主后端 |

### 2.4 Rust 内部

- `RuntimeConfig::resolved_mnn_backend()` — `"auto"` → 按 `available_backends()` 优先 `vulkan > opencl > cpu`
- `MnnModel::session_backend_names()` — 任意已加载 MNN 模型可读 session 后端
- `schedule_config()` — GPU 主后端 + `backupType = CPU`

## 3. Mauchat 后续接入清单（预估）

以下改动 **尚未在 Mauchat 实现**，可按 release 一次性接入。

### P0 — 必做（解决「看不到实际后端」）

| 文件 | 改动 |
|------|------|
| `pubspec.yaml` | 升级 `local_infer_core` ref；或 `dependency_overrides.path` 指向本地 dart |
| `lib/pages/settings/local_infer_benchmark_page.dart` | ① `RuntimeConfig` 改用 `AppConfig.localInferRuntimeConfig`，勿硬编码 `RuntimeConfig.auto()` ② `_logRuntimeHeader` 用 `tryLoadStatus(config)` 打印 `resolved_mnn_backend` ③ OCR 完成后读 `result.timings.primaryMnnSessionBackend` 打印「实际后端」④ 配置 ≠ 实际时提示回退 |
| `lib/pages/settings/local_infer_settings_page.dart` | 设备选项副标题可显示 `tryLoadStatus(selectedConfig).resolvedMnnBackend`（可选） |

Benchmark 日志目标形态：

```
runtime: mnn [cpu, opencl, vulkan]
mnn 配置后端: vulkan
...
mnn 实际后端: vulkan
```

### P1 — 设置页体验

| 场景 | 建议 |
|------|------|
| 用户选 Vulkan 但设备无 Vulkan | `filterAvailableOptions` 已有；可加 Snackbar「已回退 CPU」 |
| 切换推理设备后 | 已有 `LocalInferCache.invalidateAll()`；可加一行 debug 日志确认新 backend |
| 关于页 / 本地推理设置 | 静态展示 `runtime: mnn […]` + 当前 `resolved_mnn_backend` |

### P2 — UI 提取器对齐

| 项 | 说明 |
|----|------|
| `ui-extractor` timings | 今日 **未** 暴露 embed/OCR 的 MNN session 后端；若需要，在 ui-extractor FFI 增加 `mnn_session_backends`（与 OCR 同逻辑） |
| Benchmark UI 提取分支 | 复用 OCR 后端日志 helper，或等 ui-extractor 补齐 |

### P3 — 可选增强（local-infer-core 侧预留）

若 Mauchat 需要 **不跑 OCR 也能看实际后端**，可在 local-infer-core 增加：

```
infer_mnn_probe_backend_json(runtime_config_json, model_path, out_json)
```

轻量加载任意 `.mnn` 文件、创建 session、读 BACKENDS、立即销毁。Benchmark「仅测后端」按钮可用。

Embed engine 也可在 `EmbedEngine::load` 后暴露 `session_backend_names()`，供 icon 匹配 debug。

## 4. RuntimeConfig 约定（Android）

Mauchat `LocalInferExecutionMode` 已映射为：

| 用户选项 | `RuntimeConfig` |
|----------|-----------------|
| 自动 | `{ mnn: { backend: "vulkan" } }`（非 `"auto"` 字符串） |
| CPU | `{ mnn: { backend: "cpu" } }` |
| Vulkan | `{ mnn: { backend: "vulkan" } }` |
| OpenCL | `{ mnn: { backend: "opencl" } }` |

`local-infer-core` 的 `resolved_mnn_backend()` 仅在 `backend == "auto"` 时做 GPU 优先级解析；Mauchat 当前「自动」直接写 `vulkan`，两者一致即可。

## 5. Android Vulkan 生命周期与已知风险

### 5.1 现象

在部分 Android 设备（如 OPPO + Vulkan）上，若 **多个 MNN GPU Session 交叉销毁**（OCR 静态缓存 det/rec + embed engine），可能出现：

```
pthread_mutex_lock called on a destroyed mutex
  at Interpreter::releaseSession
```

根因：Vulkan 共享运行时被一个 engine 提前拆掉，另一 engine 的 Session 仍在 teardown。

### 5.2 local-infer-core 侧缓解（v0.1.1+）

| 机制 | 说明 |
|------|------|
| 全局 teardown 锁 | `with_teardown_lock` 串行化所有 `MnnModel::drop` |
| embed 销毁前清 OCR 缓存 | `infer_embed_engine_destroy` 先 `clear_engine_cache()` 再 drop embed |
| registry 销毁 | `infer_registry_destroy` 同样在 teardown 锁内清 OCR 缓存 |
| Session 防双释放 | `releaseSession` 后将 session 指针置空 |

### 5.3 宿主 App 建议 destroy 顺序

宿主持有多个 native handle 时，建议 **先 OCR / registry，后 embed**；切换推理设备时 **invalidate registry 再 invalidate engine**：

```
1. infer_ocr_engine_destroy(ocr)     // 若有独立 OCR handle
2. infer_registry_destroy(registry)  // 内部会 clear_engine_cache
3. infer_embed_engine_destroy(embed) // 内部也会 clear_engine_cache + drop embed
```

切换 `RuntimeConfig` / 推理设备时：

```
LocalInferCache.invalidateRegistry()  // 先
LocalInferCache.invalidateEngine()    // 后
```

> Vulkan GPU backend 在 Android 上仍属 **实验性**；若 teardown 锁后仍崩溃，见 P1b（GPU session 跳过 explicit release）或改用 CPU / OpenCL。

## 6. 版本与兼容

| local-infer-core 能力 | 最低 native 要求 |
|----------------------|------------------|
| `available` only | 任意含 `infer_runtime_backends_json` 的 build |
| `resolved_*` | 含 `infer_runtime_status_json` |
| 实际 MNN 后端 | OCR JSON 含 `mnn_session_backends` |

Dart 侧对缺失字段应 **graceful degrade**（显示「需更新 infer_core」），已在 `OcrTimings.fromJson` / `tryLoadStatus` 中处理。

## 7. 发布顺序建议

1. 发布 **local-infer-core**（含 native + dart）新版本 tag
2. Mauchat 升 ref + 改 benchmark / 设置页（P0）
3. 按需做 ui-extractor / probe API（P2/P3）
