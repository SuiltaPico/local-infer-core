import 'dart:ffi';
import 'dart:io';

import 'ffi_native.dart';

export 'ffi_native.dart' show nativeAssetId;

/// Thrown when FFI is used before the native library is available.
class LocalInferLibraryNotInitialized implements Exception {
  LocalInferLibraryNotInitialized(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _NativeLibraryKind {
  uninitialized,
  explicitPath,
  androidPlugin,
  bundledAsset,
}

_NativeLibraryKind _kind = _NativeLibraryKind.uninitialized;
DynamicLibrary? _library;

/// Whether FFI resolves symbols via build-hook [@Native] assets (desktop).
bool get usesBundledNativeAsset {
  _ensureResolved();
  return _kind == _NativeLibraryKind.bundledAsset;
}

/// Load `infer_core` from an explicit path (`.dll` / `.so` / `.dylib`).
///
/// Takes precedence over bundled assets from the build hook. Call before any
/// registry/engine API when you manage the library path yourself.
void initLocalInferCoreLibrary(String libraryPath) {
  final file = File(libraryPath);
  if (!file.existsSync()) {
    throw LocalInferLibraryNotInitialized(
      'native library not found: $libraryPath',
    );
  }
  if (Platform.isAndroid) {
    _preloadAndroidMnnRuntimePlugins();
  }
  _library = DynamicLibrary.open(libraryPath);
  _kind = _NativeLibraryKind.explicitPath;
}

/// Whether the native library has been loaded (explicitly or lazily).
bool get isLocalInferCoreLibraryInitialized =>
    _kind != _NativeLibraryKind.uninitialized;

DynamicLibrary get localInferCoreLibrary {
  _ensureResolved();
  if (_kind == _NativeLibraryKind.bundledAsset) {
    throw LocalInferLibraryNotInitialized(
      'DynamicLibrary is not used when infer_core is loaded via bundled native '
      'assets. Call initLocalInferCoreLibrary(path) if you need a DynamicLibrary '
      'handle.',
    );
  }
  return _library!;
}

/// MNN OpenCL/Vulkan backends ship as separate `.so` plugins. They register
/// runtime creators only after `dlopen`; without preload,
/// [RuntimeCapabilities.tryLoad] reports CPU-only even when the APK contains
/// `libMNN_Vulkan.so` / `libMNN_CL.so`.
void _preloadAndroidMnnRuntimePlugins() {
  for (final name in [
    'libMNN.so',
    'libMNN_Vulkan.so',
    'libMNN_CL.so',
  ]) {
    try {
      DynamicLibrary.open(name);
    } on Object {
      // Optional plugin; CPU-only installs omit GPU libs.
    }
  }
}

void _ensureResolved() {
  if (_kind != _NativeLibraryKind.uninitialized) {
    return;
  }

  if (_library != null) {
    _kind = _NativeLibraryKind.explicitPath;
    return;
  }

  if (Platform.isAndroid) {
    _preloadAndroidMnnRuntimePlugins();
    _library = DynamicLibrary.open('libinfer_core.so');
    _kind = _NativeLibraryKind.androidPlugin;
    return;
  }

  try {
    nativeInferCoreVersion();
    _kind = _NativeLibraryKind.bundledAsset;
  } on Object {
    throw LocalInferLibraryNotInitialized(
      'Call initLocalInferCoreLibrary(path) before using local_infer_core, '
      'or run `flutter pub get` so the build hook can bundle infer_core.',
    );
  }
}
