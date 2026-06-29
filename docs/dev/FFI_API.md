# local-infer-core FFI API（C ABI）

本文档基于 `crates/infer-core-ffi/src/lib.rs` 当前实现整理。  
动态库：Windows `infer_core.dll`，Linux/macOS `libinfer_core.so` / `.dylib`。

**定位**：纯 C ABI。不下载模型、不读环境变量、不提供 one-shot legacy 快捷路径。

## 1. 基础约定

- 句柄：`void*`（registry / engine / index）
- 字符串：UTF-8 `char*`
- 成功：`0`；失败：`-1`
- 错误：`out_error: char**`（需 `infer_string_free`）
- 动态字符串 / 浮点数组：分别用 `infer_string_free` / `infer_floats_free`

## 2. 公共工具

| 函数 | 说明 |
|------|------|
| `const char* infer_core_version(void)` | 版本（静态，勿 free） |
| `int infer_runtime_backends_json(char** out_json)` | `{"backend":"onnx\|mnn","available":[...]}` |
| `void infer_string_free(char* s)` | 释放库分配的字符串 |
| `void infer_floats_free(float* data, size_t len)` | 释放库分配的 float 数组 |

## 3. Registry

| 函数 | 说明 |
|------|------|
| `void* infer_registry_create(const char* models_dir, const char* runtime_config_json, char** out_error)` | `runtime_config_json` 可为 NULL/空 → `RuntimeConfig` 默认值 |
| `void infer_registry_destroy(void* handle)` | 销毁 |
| `int infer_registry_pack_ids_json(void* handle, char** out_json, char** out_error)` | pack id JSON 数组 |
| `int infer_registry_manifest_json(void* handle, const char* pack_id, char** out_json, char** out_error)` | manifest JSON |

## 4. OCR（Session 模型）

| 函数 | 说明 |
|------|------|
| `void* infer_ocr_engine_load(void* registry, const char* pack_id, char** out_error)` | 加载 OCR engine |
| `void infer_ocr_engine_destroy(void* engine)` | 销毁 |
| `int infer_ocr_engine_apply_config(void* engine, float min_confidence, uint32_t max_side, char** out_error)` | 运行时覆盖 |
| `int infer_ocr_recognize_timed(void* engine, const uint8_t* data, size_t len, char** out_json, char** out_error)` | 图片字节 → words + timings JSON |

输出 JSON：

```json
{
  "words": [{"text":"...", "bounds":{"x":0,"y":0,"width":10,"height":10}, "confidence":99.0}],
  "timings": {"init_ms": 1.0, "predict_ms": 2.0}
}
```

## 5. Embedding

| 函数 | 说明 |
|------|------|
| `void* infer_embed_engine_load(void* registry, const char* pack_id, char** out_error)` | 从 registry 加载 |
| `void* infer_embed_engine_load_path(const char* model_path, const char* runtime_config_json, char** out_error)` | 直接加载 vision 模型文件 |
| `void infer_embed_engine_destroy(void* engine)` | 销毁 |
| `float* infer_embed_rgb256(void* engine, const uint8_t* rgb256, size_t rgb_len, size_t* out_dim, char** out_error)` | 256×256×3 RGB → 向量（`infer_floats_free`） |

## 6. Icon Index

| 函数 | 说明 |
|------|------|
| `void* infer_icon_index_load(void* registry, const char* pack_id, char** out_error)` | 加载索引 |
| `void infer_icon_index_destroy(void* index)` | 销毁 |
| `int infer_icon_index_match_embedding(...)` | 最佳匹配 JSON 或 null |
| `int infer_icon_index_search(...)` | Top-K JSON 数组 |

## 7. 推荐调用顺序

1. `infer_registry_create`
2. `infer_*_engine_load` / `infer_icon_index_load`
3. 推理
4. `infer_string_free` / `infer_floats_free`
5. `*_destroy`
6. `infer_registry_destroy`

## 8. 最小示例

```c
char *err = NULL;
void *registry = infer_registry_create("/path/to/models", NULL, &err);
void *ocr = infer_ocr_engine_load(registry, "ocr.paddle.ppocr6-tiny.onnx.fp32", &err);
char *json = NULL;
infer_ocr_recognize_timed(ocr, bytes, len, &json, &err);
infer_string_free(json);
infer_ocr_engine_destroy(ocr);
infer_registry_destroy(registry);
```

模型包与动态库均由调用方从 Release 获取并放置到磁盘；本库不负责下载或环境探测。
