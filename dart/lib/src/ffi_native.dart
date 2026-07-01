import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_types.dart';

/// Bundled native asset id (see `hook/build.dart`).
const String nativeAssetId = 'package:local_infer_core/src/native_library.dart';

@Native<InferCoreVersionFn>(
  assetId: nativeAssetId,
  symbol: 'infer_core_version',
  isLeaf: true,
)
external Pointer<Utf8> nativeInferCoreVersion();

@Native<InferRuntimeBackendsJsonNative>(
  assetId: nativeAssetId,
  symbol: 'infer_runtime_backends_json',
)
external int nativeInferRuntimeBackendsJson(Pointer<Pointer<Utf8>> jsonOut);

@Native<InferRuntimeStatusJsonNative>(
  assetId: nativeAssetId,
  symbol: 'infer_runtime_status_json',
)
external int nativeInferRuntimeStatusJson(
  Pointer<Utf8> runtimeConfigJson,
  Pointer<Pointer<Utf8>> jsonOut,
);

@Native<InferStringFreeNative>(
  assetId: nativeAssetId,
  symbol: 'infer_string_free',
)
external void nativeInferStringFree(Pointer<Utf8> ptr);

@Native<InferFloatsFreeNative>(
  assetId: nativeAssetId,
  symbol: 'infer_floats_free',
)
external void nativeInferFloatsFree(Pointer<Float> ptr, int count);

@Native<InferRegistryCreateFn>(
  assetId: nativeAssetId,
  symbol: 'infer_registry_create',
)
external Pointer<Void> nativeInferRegistryCreate(
  Pointer<Utf8> modelsDir,
  Pointer<Utf8> runtimeConfigJson,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferVoidHandleNative>(
  assetId: nativeAssetId,
  symbol: 'infer_registry_destroy',
)
external void nativeInferRegistryDestroy(Pointer<Void> handle);

@Native<InferRegistryPackIdsJsonNative>(
  assetId: nativeAssetId,
  symbol: 'infer_registry_pack_ids_json',
)
external int nativeInferRegistryPackIdsJson(
  Pointer<Void> registry,
  Pointer<Pointer<Utf8>> jsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferRegistryManifestJsonNative>(
  assetId: nativeAssetId,
  symbol: 'infer_registry_manifest_json',
)
external int nativeInferRegistryManifestJson(
  Pointer<Void> registry,
  Pointer<Utf8> packId,
  Pointer<Pointer<Utf8>> jsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferOcrEngineLoadFn>(
  assetId: nativeAssetId,
  symbol: 'infer_ocr_engine_load',
)
external Pointer<Void> nativeInferOcrEngineLoad(
  Pointer<Void> registry,
  Pointer<Utf8> packId,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferVoidHandleNative>(
  assetId: nativeAssetId,
  symbol: 'infer_ocr_engine_destroy',
)
external void nativeInferOcrEngineDestroy(Pointer<Void> engine);

@Native<InferOcrEngineApplyConfigNative>(
  assetId: nativeAssetId,
  symbol: 'infer_ocr_engine_apply_config',
)
external int nativeInferOcrEngineApplyConfig(
  Pointer<Void> engine,
  double minConfidence,
  int maxSide,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferOcrRecognizeTimedNative>(
  assetId: nativeAssetId,
  symbol: 'infer_ocr_recognize_timed',
)
external int nativeInferOcrRecognizeTimed(
  Pointer<Void> engine,
  Pointer<Uint8> imageBytes,
  int imageLength,
  Pointer<Pointer<Utf8>> jsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferEmbedEngineLoadFn>(
  assetId: nativeAssetId,
  symbol: 'infer_embed_engine_load',
)
external Pointer<Void> nativeInferEmbedEngineLoad(
  Pointer<Void> registry,
  Pointer<Utf8> packId,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferEmbedEngineLoadPathFn>(
  assetId: nativeAssetId,
  symbol: 'infer_embed_engine_load_path',
)
external Pointer<Void> nativeInferEmbedEngineLoadPath(
  Pointer<Utf8> modelPath,
  Pointer<Utf8> runtimeConfigJson,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferVoidHandleNative>(
  assetId: nativeAssetId,
  symbol: 'infer_embed_engine_destroy',
)
external void nativeInferEmbedEngineDestroy(Pointer<Void> engine);

@Native<InferEmbedRgb256Native>(
  assetId: nativeAssetId,
  symbol: 'infer_embed_rgb256',
)
external Pointer<Float> nativeInferEmbedRgb256(
  Pointer<Void> engine,
  Pointer<Uint8> rgb256,
  int rgbLength,
  Pointer<IntPtr> dimOut,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferIconIndexLoadFn>(
  assetId: nativeAssetId,
  symbol: 'infer_icon_index_load',
)
external Pointer<Void> nativeInferIconIndexLoad(
  Pointer<Void> registry,
  Pointer<Utf8> packId,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferVoidHandleNative>(
  assetId: nativeAssetId,
  symbol: 'infer_icon_index_destroy',
)
external void nativeInferIconIndexDestroy(Pointer<Void> index);

@Native<InferIconIndexMatchEmbeddingNative>(
  assetId: nativeAssetId,
  symbol: 'infer_icon_index_match_embedding',
)
external int nativeInferIconIndexMatchEmbedding(
  Pointer<Void> index,
  Pointer<Float> embedding,
  int embeddingLength,
  double minCosine,
  Pointer<Pointer<Utf8>> jsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);

@Native<InferIconIndexSearchNative>(
  assetId: nativeAssetId,
  symbol: 'infer_icon_index_search',
)
external int nativeInferIconIndexSearch(
  Pointer<Void> index,
  Pointer<Float> embedding,
  int embeddingLength,
  int topK,
  Pointer<Pointer<Utf8>> jsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);
