import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_library.dart';

final class _Bindings {
  _Bindings._();

  static final _Bindings instance = _Bindings._();

  late final DynamicLibrary _lib = openLocalInferCoreLibrary();

  late final Pointer<Utf8> Function() _version =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'infer_core_version',
  );

  late final void Function(Pointer<Utf8>) _stringFree = _lib.lookupFunction<
      Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
    'infer_string_free',
  );

  late final void Function(Pointer<Float>, int) _floatsFree =
      _lib.lookupFunction<Void Function(Pointer<Float>, IntPtr),
          void Function(Pointer<Float>, int)>(
    'infer_floats_free',
  );

  late final Pointer<Void> Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
  ) _registryCreate = _lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Void> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_registry_create',
  );

  late final void Function(Pointer<Void>) _registryDestroy =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>(
    'infer_registry_destroy',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _registryPackIdsJson = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_registry_pack_ids_json',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _registryManifestJson = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_registry_manifest_json',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _ocrPlainText = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Uint8>,
        int,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_ocr_plain_text',
  );

  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
  ) _ocrEngineLoad = _lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_ocr_engine_load',
  );

  late final void Function(Pointer<Void>) _ocrEngineDestroy =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>(
    'infer_ocr_engine_destroy',
  );

  late final int Function(
    Pointer<Void>,
    double,
    int,
    Pointer<Pointer<Utf8>>,
  ) _ocrEngineApplyConfig = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Float,
        Uint32,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        double,
        int,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_ocr_engine_apply_config',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _ocrRecognizeTimed = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_ocr_recognize_timed',
  );

  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
  ) _embedEngineLoad = _lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_embed_engine_load',
  );

  late final Pointer<Void> Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
  ) _embedEngineLoadPath = _lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Void> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_embed_engine_load_path',
  );

  late final void Function(Pointer<Void>) _embedEngineDestroy =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>(
    'infer_embed_engine_destroy',
  );

  late final Pointer<Float> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<IntPtr>,
    Pointer<Pointer<Utf8>>,
  ) _embedRgb256 = _lib.lookupFunction<
      Pointer<Float> Function(
        Pointer<Void>,
        Pointer<Uint8>,
        IntPtr,
        Pointer<IntPtr>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Float> Function(
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<IntPtr>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_embed_rgb256',
  );

  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
  ) _iconIndexLoad = _lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_icon_index_load',
  );

  late final void Function(Pointer<Void>) _iconIndexDestroy =
      _lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>(
    'infer_icon_index_destroy',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Float>,
    int,
    double,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _iconIndexMatchEmbedding = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Float>,
        IntPtr,
        Float,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Float>,
        int,
        double,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_icon_index_match_embedding',
  );

  late final int Function(
    Pointer<Void>,
    Pointer<Float>,
    int,
    int,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
  ) _iconIndexSearch = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Float>,
        IntPtr,
        IntPtr,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Float>,
        int,
        int,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )>(
    'infer_icon_index_search',
  );

  String get version => _version().toDartString();

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
      return _takeOwnedString(jsonPtr.value);
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
      return _takeOwnedString(jsonPtr.value);
    } finally {
      calloc.free(packPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String ocrPlainText({
    required Pointer<Void> registry,
    required String packId,
    required Uint8List imageBytes,
  }) {
    final packPtr = packId.toNativeUtf8();
    final dataPtr = calloc<Uint8>(imageBytes.length);
    final textPtr = calloc<Pointer<Utf8>>();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      dataPtr.asTypedList(imageBytes.length).setAll(0, imageBytes);
      final rc = _ocrPlainText(
        registry,
        packPtr,
        dataPtr,
        imageBytes.length,
        textPtr,
        errorPtr,
      );
      if (rc != 0) {
        throw LocalInferException(_takeOwnedString(errorPtr.value));
      }
      return _takeOwnedString(textPtr.value);
    } finally {
      calloc.free(packPtr);
      calloc.free(dataPtr);
      calloc.free(textPtr);
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
      return _takeOwnedString(jsonPtr.value);
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
      return _takeOwnedString(jsonPtr.value);
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
      return _takeOwnedString(jsonPtr.value);
    } finally {
      calloc.free(embPtr);
      calloc.free(jsonPtr);
      calloc.free(errorPtr);
    }
  }

  String _takeOwnedString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return 'unknown native error';
    }
    try {
      return ptr.toDartString();
    } finally {
      _stringFree(ptr);
    }
  }
}

final nativeBindings = _Bindings.instance;
