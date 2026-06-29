# local_infer_core Dart API

本文档基于 `dart/lib` 当前导出接口整理（包入口：`local_infer_core.dart`）。

定位：**Flutter FFI 插件** — 运行时 `lib/` 为纯 FFI 薄封装（不读环境变量、不扫描路径）；build hook（`hook/build.dart`）负责 native 库下载/bundle；模型 zip 仍由调用方安装（见 [GitHub Releases](https://github.com/SuiltaPico/local-infer-core/releases)）。

## 1. 加载 native 库

### 方式 A：自动（推荐，Flutter 应用）

`flutter pub get` / `flutter run` / `flutter build` 时执行 `hook/build.dart`，从 GitHub Release 下载对应平台的 `infer_core` 并注册为 Native Asset。桌面端符号经 `@Native(assetId: …)` 解析；**不会**用 `DynamicLibrary.process()` 探测。

首次访问 Registry/Engine API 时，`localInferCoreLibrary` / `nativeBindings` 解析顺序：

1. 已调用 `initLocalInferCoreLibrary(path)`（显式路径，优先级最高）
2. **Android**：`DynamicLibrary.open('libinfer_core.so')`（ffiPlugin 打包）
3. **Windows 等桌面**：build hook 产出的 bundled 库（`@Native`）

### 方式 B：手动路径（测试 / 自定义布局）

```dart
import 'package:local_infer_core/local_infer_core.dart';

initLocalInferCoreLibrary(r'C:\path\to\infer_core.dll');
```

须在首次 Registry/Engine 调用**之前**执行。环境变量、配置文件由调用方读取后传入路径；本包不介入。

### Build hook 配置（根应用 `pubspec.yaml`）

仅 **根应用** 可配置 `hooks.user_defines.local_infer_core`：

```yaml
hooks:
  user_defines:
    local_infer_core:
      skip_download: true
      local_lib: ../local-infer-core/target/release/infer_core.dll
      release_repo: SuiltaPico/local-infer-core
      release_tag: v0.1.0
```

| 键 | 说明 |
|----|------|
| `skip_download` | 为 `true` 时 hook 不产出 CodeAsset |
| `local_lib` | 显式本地 `.dll` / `.so`（相对根应用 pubspec）；monorepo 开发推荐此项 |
| `release_repo` / `release_tag` | 覆盖 `assets/catalog.json` 中的默认 Release 源 |

Hook 解析顺序（**仅两步，无静默 fallback**）：

1. `local_lib`（显式）
2. 否则从 `release_repo` / `release_tag` 下载（默认读 `assets/catalog.json` 的 `release` 段）

### API 一览

| API | 说明 |
|-----|------|
| `initLocalInferCoreLibrary(String libraryPath)` | 显式加载（覆盖 bundled） |
| `isLocalInferCoreLibraryInitialized` | 是否已加载（含 lazy resolve） |
| `usesBundledNativeAsset` | 是否经 build hook `@Native` 解析符号 |
| `LocalInferLibraryNotInitialized` | 无法解析 native 库时抛出 |

### 模型包与 catalog

模型包由调用方下载 Release zip，解压到 `{models_dir}/{pack_id}/`（含 `manifest.json`）。

`assets/catalog.json` 提供官方 pack 清单与 sha256。读取 API：

```dart
final catalog = await PackCatalog.loadFromAssetBundle();
final pack = catalog.findPack('ocr.paddle.ppocr6-tiny.onnx.fp32');
```

## 2. 包入口导出

- `native_library.dart` — 库加载
- `pack_catalog.dart` — 官方模型 catalog
- `registry.dart` — Registry
- `ocr_engine.dart` / `embed_engine.dart` / `icon_index.dart`
- `runtime_config.dart` / `runtime_capabilities.dart`
- `exceptions.dart`

## 3. Runtime 配置与能力

### `OnnxConfig` / `MnnConfig` / `RuntimeConfig`

与 Rust `RuntimeConfig` JSON 一一对应。工厂：

- `RuntimeConfig.auto()` — 显式传入 `execution_providers: ['auto']`（由 native 按平台展开 EP）
- `RuntimeConfig.cpu()` — 纯 CPU

### `RuntimeCapabilities`

- `RuntimeCapabilities.tryLoad()` — 查询 native 编译后端与可用 EP/MNN backend

## 4. Registry API

### `LocalInferRegistry`

- `static Future<LocalInferRegistry> open({required String modelsDir, RuntimeConfig runtimeConfig = const RuntimeConfig()})`
- `LocalOcrEngine ocr(String packId)`
- `LocalEmbedEngine embed(String packId)`
- `LocalEmbedModel embedFromPath(String modelPath, {RuntimeConfig? runtimeConfig})`
- `LocalIconIndex iconIndex(String packId)`
- `Future<List<String>> packIds()`
- `Future<Map<String, dynamic>> manifest(String packId)`
- `void dispose()`

> **Async 说明**：上述 `Future` 方法当前为同步 FFI 的 async 包装（无 isolate/IO）；签名保留以便日后扩展，调用方不必 `await` 多个并发请求，但应知悉当前无真正异步。

## 5. OCR API

### Session 模型（推荐）

- `LocalOcrEngine.openSession()` → `LocalOcrSession`
- `LocalOcrSession.recognizeTimed(Uint8List)` → `OcrRecognizeResult`
- `LocalOcrSession.plainText(Uint8List)` — 基于 session，词级结果拼接

`LocalOcrEngine.plainText` / `recognizeTimed` 为便捷 one-shot（内部 open → 调用 → dispose）。

## 6. Embedding API

- `LocalEmbedSession.embedRgb256(Uint8List)` — 输入 `256×256×3` RGB 原始字节
- `LocalEmbedEngine` / `LocalEmbedModel` — 与 OCR 相同的 session / one-shot 模式

## 7. Icon Index API

- `LocalIconIndexSession.matchEmbedding(Float32List, {minCosine})`
- `LocalIconIndexSession.search(Float32List, {topK})`

## 8. 异常

- `LocalInferException` — native 返回的错误文本
- `LocalInferLibraryNotInitialized` — native 库未加载且无法自动解析

## 9. 最小示例

### Flutter（自动加载）

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:local_infer_core/local_infer_core.dart';

// hook 已在 flutter pub get / flutter run 时下载并 bundle infer_core.dll

final catalog = await PackCatalog.loadFromAssetBundle();

final registry = await LocalInferRegistry.open(
  modelsDir: r'D:\models',
  runtimeConfig: RuntimeConfig.cpu(),
);

final session = await registry
    .ocr('ocr.paddle.ppocr6-tiny.onnx.fp32')
    .openSession();
try {
  final bytes = await File('screenshot.png').readAsBytes();
  final result = await session.recognizeTimed(bytes);
  print(result.words.map((w) => w.text).join('\n'));
} finally {
  session.dispose();
  registry.dispose();
}
```

### 显式 native 路径（集成测试）

```dart
initLocalInferCoreLibrary(r'D:\libs\infer_core.dll');

final registry = await LocalInferRegistry.open(
  modelsDir: r'D:\models',
  runtimeConfig: RuntimeConfig.cpu(),
);
// ...
```
