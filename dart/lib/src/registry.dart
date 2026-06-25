import 'dart:convert';
import 'dart:ffi';

import 'embed_engine.dart';
import 'ffi_bindings.dart';
import 'icon_index.dart';
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

  LocalEmbedEngine embed(String packId) {
    return LocalEmbedEngine(registry: this, packId: packId);
  }

  LocalEmbedModel embedFromPath(
    String modelPath, {
    RuntimeConfig? runtimeConfig,
  }) {
    return LocalEmbedModel(
      modelPath: modelPath,
      runtimeConfig: runtimeConfig ?? this.runtimeConfig,
    );
  }

  LocalIconIndex iconIndex(String packId) {
    return LocalIconIndex(registry: this, packId: packId);
  }

  Pointer<Void> get nativeHandle => _handle;

  Future<List<String>> packIds() async {
    final jsonText = nativeBindings.registryPackIdsJson(registry: _handle);
    final decoded = jsonDecode(jsonText) as List<dynamic>;
    return decoded.map((e) => e.toString()).toList(growable: false);
  }

  Future<Map<String, dynamic>> manifest(String packId) async {
    final jsonText = nativeBindings.registryManifestJson(
      registry: _handle,
      packId: packId,
    );
    return (jsonDecode(jsonText) as Map).cast<String, dynamic>();
  }

  void dispose() {
    nativeBindings.destroyRegistry(_handle);
  }
}
