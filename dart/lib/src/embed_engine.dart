import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'ffi_bindings.dart';
import 'registry.dart';
import 'runtime_config.dart';

class LocalEmbedSession {
  LocalEmbedSession._(this._handle);

  final Pointer<Void> _handle;
  bool _disposed = false;

  Future<Float32List> embedRgb256(Uint8List rgb256) async {
    _assertNotDisposed();
    return nativeBindings.embedRgb256(engine: _handle, rgb256: rgb256);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_handle != nullptr) {
      nativeBindings.embedEngineDestroy(_handle);
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('LocalEmbedSession is disposed');
    }
  }
}

class LocalEmbedEngine {
  const LocalEmbedEngine({
    required this.registry,
    required this.packId,
  });

  final LocalInferRegistry registry;
  final String packId;

  Future<LocalEmbedSession> openSession() async {
    final handle = nativeBindings.embedEngineLoad(
      registry: registry.nativeHandle,
      packId: packId,
    );
    return LocalEmbedSession._(handle);
  }

  Future<Float32List> embedRgb256(Uint8List rgb256) async {
    final session = await openSession();
    try {
      return session.embedRgb256(rgb256);
    } finally {
      session.dispose();
    }
  }
}

class LocalEmbedModel {
  const LocalEmbedModel({
    required this.modelPath,
    this.runtimeConfig = const RuntimeConfig(),
  });

  final String modelPath;
  final RuntimeConfig runtimeConfig;

  Future<LocalEmbedSession> openSession() async {
    final handle = nativeBindings.embedEngineLoadPath(
      modelPath: modelPath,
      runtimeConfigJson: jsonEncode(runtimeConfig.toJson()),
    );
    return LocalEmbedSession._(handle);
  }

  Future<Float32List> embedRgb256(Uint8List rgb256) async {
    final session = await openSession();
    try {
      return session.embedRgb256(rgb256);
    } finally {
      session.dispose();
    }
  }
}
