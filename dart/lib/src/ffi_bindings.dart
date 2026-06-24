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

  late final void Function(Pointer<Utf8>) _stringFree =
      _lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
    'infer_string_free',
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
      _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
    'infer_registry_destroy',
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
