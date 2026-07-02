import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'ffi_native.dart';
import 'ffi_types.dart';
import 'native_library.dart';

final class _Bindings {
  _Bindings._() {
    if (usesBundledNativeAsset) {
      _initBundled();
    } else {
      _initDynamicLibrary(localInferCoreLibrary);
    }
  }

  static final _Bindings instance = _Bindings._();

  late final InferCoreVersionFn _version;
  InferRuntimeBackendsJsonFn? _runtimeBackendsJsonFn;
  InferRuntimeStatusJsonFn? _runtimeStatusJsonFn;
  late final InferStringFreeFn _stringFree;
  late final InferFloatsFreeFn _floatsFree;
  late final InferRegistryCreateFn _registryCreate;
  late final InferRegistryDestroyFn _registryDestroy;
  late final InferRegistryPackIdsJsonFn _registryPackIdsJson;
  late final InferRegistryManifestJsonFn _registryManifestJson;
  InferRegistryWarmUpMnnGpuFn? _registryWarmUpMnnGpu;
  late final InferOcrEngineLoadFn _ocrEngineLoad;
  late final InferOcrEngineDestroyFn _ocrEngineDestroy;
  late final InferOcrEngineApplyConfigFn _ocrEngineApplyConfig;
  late final InferOcrRecognizeTimedFn _ocrRecognizeTimed;
  late final InferOcrRecognizeRgbTimedFn _ocrRecognizeRgbTimed;
  late final InferEmbedEngineLoadFn _embedEngineLoad;
  late final InferEmbedEngineLoadPathFn _embedEngineLoadPath;
  late final InferEmbedEngineDestroyFn _embedEngineDestroy;
  late final InferEmbedRgb256Fn _embedRgb256;
  late final InferIconIndexLoadFn _iconIndexLoad;
  late final InferIconIndexDestroyFn _iconIndexDestroy;
  late final InferIconIndexMatchEmbeddingFn _iconIndexMatchEmbedding;
  late final InferIconIndexSearchFn _iconIndexSearch;

  void _initBundled() {
    _version = nativeInferCoreVersion;
    _runtimeBackendsJsonFn = nativeInferRuntimeBackendsJson;
    _runtimeStatusJsonFn = nativeInferRuntimeStatusJson;
    _stringFree = nativeInferStringFree;
    _floatsFree = nativeInferFloatsFree;
    _registryCreate = nativeInferRegistryCreate;
    _registryDestroy = nativeInferRegistryDestroy;
    _registryPackIdsJson = nativeInferRegistryPackIdsJson;
    _registryManifestJson = nativeInferRegistryManifestJson;
    _registryWarmUpMnnGpu = nativeInferRegistryWarmUpMnnGpu;
    _ocrEngineLoad = nativeInferOcrEngineLoad;
    _ocrEngineDestroy = nativeInferOcrEngineDestroy;
    _ocrEngineApplyConfig = nativeInferOcrEngineApplyConfig;
    _ocrRecognizeTimed = nativeInferOcrRecognizeTimed;
    _ocrRecognizeRgbTimed = nativeInferOcrRecognizeRgbTimed;
    _embedEngineLoad = nativeInferEmbedEngineLoad;
    _embedEngineLoadPath = nativeInferEmbedEngineLoadPath;
    _embedEngineDestroy = nativeInferEmbedEngineDestroy;
    _embedRgb256 = nativeInferEmbedRgb256;
    _iconIndexLoad = nativeInferIconIndexLoad;
    _iconIndexDestroy = nativeInferIconIndexDestroy;
    _iconIndexMatchEmbedding = nativeInferIconIndexMatchEmbedding;
    _iconIndexSearch = nativeInferIconIndexSearch;
  }

  void _initDynamicLibrary(DynamicLibrary lib) {
    _runtimeBackendsJsonFn = () {
      try {
        return lib.lookupFunction<
            InferRuntimeBackendsJsonNative, InferRuntimeBackendsJsonFn>(
          'infer_runtime_backends_json',
        );
      } on Object {
        return null;
      }
    }();
    _runtimeStatusJsonFn = () {
      try {
        return lib.lookupFunction<
            InferRuntimeStatusJsonNative, InferRuntimeStatusJsonFn>(
          'infer_runtime_status_json',
        );
      } on Object {
        return null;
      }
    }();
    _version = lib.lookupFunction<InferCoreVersionFn, InferCoreVersionFn>(
      'infer_core_version',
    );
    _stringFree = lib.lookupFunction<InferStringFreeNative, InferStringFreeFn>(
      'infer_string_free',
    );
    _floatsFree = lib.lookupFunction<InferFloatsFreeNative, InferFloatsFreeFn>(
      'infer_floats_free',
    );
    _registryCreate =
        lib.lookupFunction<InferRegistryCreateFn, InferRegistryCreateFn>(
      'infer_registry_create',
    );
    _registryDestroy =
        lib.lookupFunction<InferVoidHandleNative, InferRegistryDestroyFn>(
      'infer_registry_destroy',
    );
    _registryPackIdsJson = lib.lookupFunction<
        InferRegistryPackIdsJsonNative, InferRegistryPackIdsJsonFn>(
      'infer_registry_pack_ids_json',
    );
    _registryManifestJson = lib.lookupFunction<
        InferRegistryManifestJsonNative, InferRegistryManifestJsonFn>(
      'infer_registry_manifest_json',
    );
    _registryWarmUpMnnGpu = () {
      try {
        return lib.lookupFunction<
            InferRegistryWarmUpMnnGpuNative, InferRegistryWarmUpMnnGpuFn>(
          'infer_registry_warm_up_mnn_gpu',
        );
      } on Object {
        return null;
      }
    }();
    _ocrEngineLoad =
        lib.lookupFunction<InferOcrEngineLoadFn, InferOcrEngineLoadFn>(
      'infer_ocr_engine_load',
    );
    _ocrEngineDestroy =
        lib.lookupFunction<InferVoidHandleNative, InferOcrEngineDestroyFn>(
      'infer_ocr_engine_destroy',
    );
    _ocrEngineApplyConfig = lib.lookupFunction<
        InferOcrEngineApplyConfigNative, InferOcrEngineApplyConfigFn>(
      'infer_ocr_engine_apply_config',
    );
    _ocrRecognizeTimed = lib.lookupFunction<
        InferOcrRecognizeTimedNative, InferOcrRecognizeTimedFn>(
      'infer_ocr_recognize_timed',
    );
    _ocrRecognizeRgbTimed = lib.lookupFunction<
        InferOcrRecognizeRgbTimedNative, InferOcrRecognizeRgbTimedFn>(
      'infer_ocr_recognize_rgb_timed',
    );
    _embedEngineLoad =
        lib.lookupFunction<InferEmbedEngineLoadFn, InferEmbedEngineLoadFn>(
      'infer_embed_engine_load',
    );
    _embedEngineLoadPath = lib.lookupFunction<
        InferEmbedEngineLoadPathFn, InferEmbedEngineLoadPathFn>(
      'infer_embed_engine_load_path',
    );
    _embedEngineDestroy =
        lib.lookupFunction<InferVoidHandleNative, InferEmbedEngineDestroyFn>(
      'infer_embed_engine_destroy',
    );
    _embedRgb256 =
        lib.lookupFunction<InferEmbedRgb256Native, InferEmbedRgb256Fn>(
      'infer_embed_rgb256',
    );
    _iconIndexLoad =
        lib.lookupFunction<InferIconIndexLoadFn, InferIconIndexLoadFn>(
      'infer_icon_index_load',
    );
    _iconIndexDestroy =
        lib.lookupFunction<InferVoidHandleNative, InferIconIndexDestroyFn>(
      'infer_icon_index_destroy',
    );
    _iconIndexMatchEmbedding = lib.lookupFunction<
        InferIconIndexMatchEmbeddingNative, InferIconIndexMatchEmbeddingFn>(
      'infer_icon_index_match_embedding',
    );
    _iconIndexSearch = lib.lookupFunction<
        InferIconIndexSearchNative, InferIconIndexSearchFn>(
      'infer_icon_index_search',
    );
  }

  int Function(Pointer<Pointer<Utf8>>)? get _runtimeBackendsJsonFnOrNull =>
      _runtimeBackendsJsonFn;

  int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)?
      get _runtimeStatusJsonFnOrNull => _runtimeStatusJsonFn;

  String get version => _version().toDartString();

  /// Returns JSON from native when supported; null on older libraries.
  String? runtimeBackendsJson() {
    final fn = _runtimeBackendsJsonFnOrNull;
    if (fn == null) return null;
    final jsonPtr = calloc<Pointer<Utf8>>();
    try {
      final rc = fn(jsonPtr);
      if (rc != 0) {
        return null;
      }
      return _requireOwnedString(jsonPtr.value, 'runtimeBackendsJson');
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Returns runtime status JSON for [runtimeConfigJson]; null when unsupported.
  String? runtimeStatusJson(String runtimeConfigJson) {
    final fn = _runtimeStatusJsonFnOrNull;
    if (fn != null) {
      final configPtr = runtimeConfigJson.toNativeUtf8();
      final jsonPtr = calloc<Pointer<Utf8>>();
      try {
        final rc = fn(configPtr, jsonPtr);
        if (rc == 0) {
          return _requireOwnedString(jsonPtr.value, 'runtimeStatusJson');
        }
      } finally {
        calloc.free(configPtr);
        calloc.free(jsonPtr);
      }
    }
    return runtimeBackendsJson();
  }

  Pointer<Void> createRegistry({
    required String modelsDir,
    String runtimeConfigJson = '',
  }) {
    final dirPtr = modelsDir.toNativeUtf8();
    final configPtr = runtimeConfigJson.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final handle = _registryCreate(dirPtr, configPtr, errorPtr);
      if (handle == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return handle;
    } finally {
      calloc.free(dirPtr);
      calloc.free(configPtr);
      calloc.free(errorPtr);
    }
  }

  void destroyRegistry(Pointer<Void> handle) {
    _registryDestroy(handle);
  }

  String registryPackIdsJson({
    required Pointer<Void> registry,
  }) {
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final rc = _registryPackIdsJson(registry, jsonPtr, errorPtr);
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'registryPackIdsJson');
    } finally {
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String registryManifestJson({
    required Pointer<Void> registry,
    required String packId,
  }) {
    final packPtr = packId.toNativeUtf8();
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final rc = _registryManifestJson(registry, packPtr, jsonPtr, errorPtr);
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'registryManifestJson');
    } finally {
      calloc.free(packPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  void registryWarmUpMnnGpu({
    required Pointer<Void> registry,
    required String ocrPackId,
    required String embedPackId,
    required int ocrMaxSide,
  }) {
    final fn = _registryWarmUpMnnGpu;
    if (fn == null) {
      return;
    }
    final ocrPtr = ocrPackId.toNativeUtf8();
    final embedPtr = embedPackId.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final rc = fn(registry, ocrPtr, embedPtr, ocrMaxSide, errorPtr);
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
    } finally {
      calloc.free(ocrPtr);
      calloc.free(embedPtr);
      calloc.free(errorPtr);
    }
  }

  Pointer<Void> ocrEngineLoad({
    required Pointer<Void> registry,
    required String packId,
  }) {
    final packPtr = packId.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final handle = _ocrEngineLoad(registry, packPtr, errorPtr);
      if (handle == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return handle;
    } finally {
      calloc.free(packPtr);
      calloc.free(errorPtr);
    }
  }

  void ocrEngineDestroy(Pointer<Void> engine) => _ocrEngineDestroy(engine);

  void ocrEngineApplyConfig({
    required Pointer<Void> engine,
    required double minConfidence,
    required int maxSide,
  }) {
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final rc =
          _ocrEngineApplyConfig(engine, minConfidence, maxSide, errorPtr);
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
    } finally {
      calloc.free(errorPtr);
    }
  }

  String ocrRecognizeTimed({
    required Pointer<Void> engine,
    required Uint8List imageBytes,
  }) {
    final dataPtr = calloc<Uint8>(imageBytes.length);
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      dataPtr.asTypedList(imageBytes.length).setAll(0, imageBytes);
      final rc = _ocrRecognizeTimed(
        engine,
        dataPtr,
        imageBytes.length,
        jsonPtr,
        errorPtr,
      );
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'ocrRecognizeTimed');
    } finally {
      calloc.free(dataPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String ocrRecognizeRgbTimed({
    required Pointer<Void> engine,
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) {
    final dataPtr = calloc<Uint8>(rgbBytes.length);
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      dataPtr.asTypedList(rgbBytes.length).setAll(0, rgbBytes);
      final rc = _ocrRecognizeRgbTimed(
        engine,
        dataPtr,
        rgbBytes.length,
        width,
        height,
        jsonPtr,
        errorPtr,
      );
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'ocrRecognizeRgbTimed');
    } finally {
      calloc.free(dataPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  Pointer<Void> embedEngineLoad({
    required Pointer<Void> registry,
    required String packId,
  }) {
    final packPtr = packId.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final handle = _embedEngineLoad(registry, packPtr, errorPtr);
      if (handle == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return handle;
    } finally {
      calloc.free(packPtr);
      calloc.free(errorPtr);
    }
  }

  Pointer<Void> embedEngineLoadPath({
    required String modelPath,
    String runtimeConfigJson = '',
  }) {
    final pathPtr = modelPath.toNativeUtf8();
    final configPtr = runtimeConfigJson.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final handle = _embedEngineLoadPath(pathPtr, configPtr, errorPtr);
      if (handle == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return handle;
    } finally {
      calloc.free(pathPtr);
      calloc.free(configPtr);
      calloc.free(errorPtr);
    }
  }

  void embedEngineDestroy(Pointer<Void> engine) => _embedEngineDestroy(engine);

  Float32List embedRgb256({
    required Pointer<Void> engine,
    required Uint8List rgb256,
  }) {
    final dataPtr = calloc<Uint8>(rgb256.length);
    final dimPtr = calloc<IntPtr>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      dataPtr.asTypedList(rgb256.length).setAll(0, rgb256);
      final outPtr =
          _embedRgb256(engine, dataPtr, rgb256.length, dimPtr, errorPtr);
      if (outPtr == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      final dim = dimPtr.value;
      final copied = Float32List.fromList(outPtr.asTypedList(dim));
      _floatsFree(outPtr, dim);
      return copied;
    } finally {
      calloc.free(dataPtr);
      calloc.free(dimPtr);
      calloc.free(errorPtr);
    }
  }

  Pointer<Void> iconIndexLoad({
    required Pointer<Void> registry,
    required String packId,
  }) {
    final packPtr = packId.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final handle = _iconIndexLoad(registry, packPtr, errorPtr);
      if (handle == nullptr) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return handle;
    } finally {
      calloc.free(packPtr);
      calloc.free(errorPtr);
    }
  }

  void iconIndexDestroy(Pointer<Void> index) => _iconIndexDestroy(index);

  String iconIndexMatchEmbeddingJson({
    required Pointer<Void> index,
    required Float32List embedding,
    required double minCosine,
  }) {
    final embPtr = calloc<Float>(embedding.length);
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      embPtr.asTypedList(embedding.length).setAll(0, embedding);
      final rc = _iconIndexMatchEmbedding(
        index,
        embPtr,
        embedding.length,
        minCosine,
        jsonPtr,
        errorPtr,
      );
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'iconIndexMatchEmbedding');
    } finally {
      calloc.free(embPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String iconIndexSearchJson({
    required Pointer<Void> index,
    required Float32List embedding,
    required int topK,
  }) {
    final embPtr = calloc<Float>(embedding.length);
    final jsonPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      embPtr.asTypedList(embedding.length).setAll(0, embedding);
      final rc = _iconIndexSearch(
        index,
        embPtr,
        embedding.length,
        topK,
        jsonPtr,
        errorPtr,
      );
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _requireOwnedString(jsonPtr.value, 'iconIndexSearch');
    } finally {
      calloc.free(embPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String? _takeOwnedStringOrNull(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return null;
    }
    try {
      return ptr.toDartString();
    } finally {
      _stringFree(ptr);
    }
  }

  String _requireOwnedString(Pointer<Utf8> ptr, String context) {
    final value = _takeOwnedStringOrNull(ptr);
    if (value == null) {
      throw LocalInferException('native returned no JSON ($context)');
    }
    return value;
  }

  String _takeOwnedString(Pointer<Utf8> ptr) {
    return _takeOwnedStringOrNull(ptr) ?? 'unknown native error';
  }
}

final nativeBindings = _Bindings.instance;
