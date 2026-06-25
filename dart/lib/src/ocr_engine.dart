import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'ffi_bindings.dart';
import 'registry.dart';

class OcrBounds {
  const OcrBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  factory OcrBounds.fromJson(Map<String, dynamic> json) {
    return OcrBounds(
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class OcrWord {
  const OcrWord({
    required this.text,
    required this.bounds,
    required this.confidence,
  });

  final String text;
  final OcrBounds bounds;
  final double confidence;

  factory OcrWord.fromJson(Map<String, dynamic> json) {
    return OcrWord(
      text: json['text']?.toString() ?? '',
      bounds: OcrBounds.fromJson(
          (json['bounds'] as Map<String, dynamic>?) ?? const {}),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OcrTimings {
  const OcrTimings({
    required this.initMs,
    required this.predictMs,
  });

  final double initMs;
  final double predictMs;

  factory OcrTimings.fromJson(Map<String, dynamic> json) {
    return OcrTimings(
      initMs: (json['init_ms'] as num?)?.toDouble() ?? 0,
      predictMs: (json['predict_ms'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OcrRecognizeResult {
  const OcrRecognizeResult({
    required this.words,
    required this.timings,
  });

  final List<OcrWord> words;
  final OcrTimings timings;

  factory OcrRecognizeResult.fromJson(Map<String, dynamic> json) {
    final rawWords = (json['words'] as List<dynamic>?) ?? const [];
    final words = rawWords
        .map((e) => OcrWord.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
    return OcrRecognizeResult(
      words: words,
      timings: OcrTimings.fromJson(
          (json['timings'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}

class LocalOcrSession {
  LocalOcrSession._(this._handle);

  final Pointer<Void> _handle;
  bool _disposed = false;

  void applyConfig({
    required double minConfidence,
    required int maxSide,
  }) {
    _assertNotDisposed();
    nativeBindings.ocrEngineApplyConfig(
      engine: _handle,
      minConfidence: minConfidence,
      maxSide: maxSide,
    );
  }

  Future<OcrRecognizeResult> recognizeTimed(Uint8List imageBytes) async {
    _assertNotDisposed();
    final jsonText = nativeBindings.ocrRecognizeTimed(
        engine: _handle, imageBytes: imageBytes);
    return OcrRecognizeResult.fromJson(
      (jsonDecode(jsonText) as Map).cast<String, dynamic>(),
    );
  }

  Future<String> plainText(Uint8List imageBytes) async {
    final result = await recognizeTimed(imageBytes);
    return result.words.map((w) => w.text).join('\n');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_handle != nullptr) {
      nativeBindings.ocrEngineDestroy(_handle);
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('LocalOcrSession is disposed');
    }
  }
}

class LocalOcrEngine {
  const LocalOcrEngine({
    required this.registry,
    required this.packId,
  });

  final LocalInferRegistry registry;
  final String packId;

  Future<LocalOcrSession> openSession({
    double? minConfidence,
    int? maxSide,
  }) async {
    final handle = nativeBindings.ocrEngineLoad(
      registry: registry.nativeHandle,
      packId: packId,
    );
    final session = LocalOcrSession._(handle);
    if (minConfidence != null || maxSide != null) {
      session.applyConfig(
        minConfidence: minConfidence ?? 0.5,
        maxSide: maxSide ?? 960,
      );
    }
    return session;
  }

  Future<String> plainText(Uint8List imageBytes) async {
    return nativeBindings.ocrPlainText(
      registry: registry.nativeHandle,
      packId: packId,
      imageBytes: imageBytes,
    );
  }

  Future<OcrRecognizeResult> recognizeTimed(
    Uint8List imageBytes, {
    double? minConfidence,
    int? maxSide,
  }) async {
    final session = await openSession(
      minConfidence: minConfidence,
      maxSide: maxSide,
    );
    try {
      return session.recognizeTimed(imageBytes);
    } finally {
      session.dispose();
    }
  }
}
