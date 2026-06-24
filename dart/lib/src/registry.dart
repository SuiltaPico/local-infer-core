import 'dart:convert';
import 'dart:ffi';

import 'ffi_bindings.dart';
import 'ocr_engine.dart';
import 'runtime_config.dart';

class LocalInferRegistry {
  LocalInferRegistry._({
    required this.modelsDir,
    required this.runtimeConfig,
    required Pointer<Void> handle,
  }) : _handle = handle;

  final String modelsDir;
  final RuntimeConfig runtimeConfig;
  final Pointer<Void> _handle;

  static Future<LocalInferRegistry> open({
    required String modelsDir,
    RuntimeConfig runtimeConfig = const RuntimeConfig(),
  }) async {
    final handle = nativeBindings.createRegistry(
      modelsDir: modelsDir,
      runtimeConfigJson: jsonEncode(runtimeConfig.toJson()),
    );
    return LocalInferRegistry._(
      modelsDir: modelsDir,
      runtimeConfig: runtimeConfig,
      handle: handle,
    );
  }

  LocalOcrEngine ocr(String packId) {
    return LocalOcrEngine(registry: this, packId: packId);
  }

  Pointer<Void> get nativeHandle => _handle;

  void dispose() {
    nativeBindings.destroyRegistry(_handle);
  }
}
