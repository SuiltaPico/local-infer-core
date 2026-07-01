import 'dart:ffi';

import 'package:ffi/ffi.dart';

// --- Shared (native ABI matches Dart callable) ---

typedef InferCoreVersionFn = Pointer<Utf8> Function();

typedef InferStringFreeFn = void Function(Pointer<Utf8>);

typedef InferRegistryCreateFn = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferRegistryDestroyFn = void Function(Pointer<Void>);

typedef InferOcrEngineLoadFn = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferOcrEngineDestroyFn = void Function(Pointer<Void>);

typedef InferEmbedEngineLoadFn = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferEmbedEngineLoadPathFn = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferEmbedEngineDestroyFn = void Function(Pointer<Void>);

typedef InferIconIndexLoadFn = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferIconIndexDestroyFn = void Function(Pointer<Void>);

// --- Native ABI differs from Dart callable (IntPtr / Float / Int32) ---

typedef InferRuntimeBackendsJsonNative = Int32 Function(Pointer<Pointer<Utf8>>);
typedef InferRuntimeBackendsJsonFn = int Function(Pointer<Pointer<Utf8>>);

typedef InferRuntimeStatusJsonNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);
typedef InferRuntimeStatusJsonFn = int Function(
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);

typedef InferFloatsFreeNative = Void Function(Pointer<Float>, IntPtr);
typedef InferFloatsFreeFn = void Function(Pointer<Float>, int);

typedef InferRegistryPackIdsJsonNative = Int32 Function(
  Pointer<Void>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferRegistryPackIdsJsonFn = int Function(
  Pointer<Void>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferRegistryManifestJsonNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferRegistryManifestJsonFn = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferOcrEngineApplyConfigNative = Int32 Function(
  Pointer<Void>,
  Float,
  Uint32,
  Pointer<Pointer<Utf8>>,
);
typedef InferOcrEngineApplyConfigFn = int Function(
  Pointer<Void>,
  double,
  int,
  Pointer<Pointer<Utf8>>,
);

typedef InferOcrRecognizeTimedNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferOcrRecognizeTimedFn = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferOcrRecognizeRgbTimedNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
  Uint32,
  Uint32,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferOcrRecognizeRgbTimedFn = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  int,
  int,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferEmbedRgb256Native = Pointer<Float> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
  Pointer<IntPtr>,
  Pointer<Pointer<Utf8>>,
);
typedef InferEmbedRgb256Fn = Pointer<Float> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<IntPtr>,
  Pointer<Pointer<Utf8>>,
);

typedef InferIconIndexMatchEmbeddingNative = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  IntPtr,
  Float,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferIconIndexMatchEmbeddingFn = int Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  double,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferIconIndexSearchNative = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  IntPtr,
  IntPtr,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef InferIconIndexSearchFn = int Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  int,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

typedef InferVoidHandleNative = Void Function(Pointer<Void>);

typedef InferStringFreeNative = Void Function(Pointer<Utf8>);
