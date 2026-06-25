import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'ffi_bindings.dart';
import 'registry.dart';

class IconMatch {
  const IconMatch({
    required this.name,
    required this.score,
  });

  final String name;
  final double score;

  factory IconMatch.fromJson(Map<String, dynamic> json) {
    return IconMatch(
      name: json['name']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }
}

class LocalIconIndexSession {
  LocalIconIndexSession._(this._handle);

  final Pointer<Void> _handle;
  bool _disposed = false;

  Future<IconMatch?> matchEmbedding(
    Float32List embedding, {
    double minCosine = 0.0,
  }) async {
    _assertNotDisposed();
    final jsonText = nativeBindings.iconIndexMatchEmbeddingJson(
      index: _handle,
      embedding: embedding,
      minCosine: minCosine,
    );
    final decoded = jsonDecode(jsonText);
    if (decoded == null) {
      return null;
    }
    return IconMatch.fromJson((decoded as Map).cast<String, dynamic>());
  }

  Future<List<IconMatch>> search(
    Float32List embedding, {
    int topK = 5,
  }) async {
    _assertNotDisposed();
    final jsonText = nativeBindings.iconIndexSearchJson(
      index: _handle,
      embedding: embedding,
      topK: topK,
    );
    final decoded = jsonDecode(jsonText) as List<dynamic>;
    return decoded
        .map((e) => IconMatch.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_handle != nullptr) {
      nativeBindings.iconIndexDestroy(_handle);
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('LocalIconIndexSession is disposed');
    }
  }
}

class LocalIconIndex {
  const LocalIconIndex({
    required this.registry,
    required this.packId,
  });

  final LocalInferRegistry registry;
  final String packId;

  Future<LocalIconIndexSession> openSession() async {
    final handle = nativeBindings.iconIndexLoad(
      registry: registry.nativeHandle,
      packId: packId,
    );
    return LocalIconIndexSession._(handle);
  }

  Future<IconMatch?> matchEmbedding(
    Float32List embedding, {
    double minCosine = 0.0,
  }) async {
    final session = await openSession();
    try {
      return session.matchEmbedding(embedding, minCosine: minCosine);
    } finally {
      session.dispose();
    }
  }

  Future<List<IconMatch>> search(
    Float32List embedding, {
    int topK = 5,
  }) async {
    final session = await openSession();
    try {
      return session.search(embedding, topK: topK);
    } finally {
      session.dispose();
    }
  }
}
