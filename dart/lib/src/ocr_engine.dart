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
    this.decodeMs = 0,
    this.resizeMs = 0,
    this.detMs = 0,
    this.recMs = 0,
    this.postMs = 0,
    this.mnnConfiguredBackend,
    this.mnnSessionBackends = const [],
  });

  final double initMs;
  final double predictMs;
  final double decodeMs;
  final double resizeMs;
  final double detMs;
  final double recMs;
  final double postMs;
  final String? mnnConfiguredBackend;
  final List<String> mnnSessionBackends;

  String? get primaryMnnSessionBackend =>
      mnnSessionBackends.isEmpty ? null : mnnSessionBackends.first;

  factory OcrTimings.fromJson(Map<String, dynamic> json) {
    final rawBackends = json['mnn_session_backends'];
    return OcrTimings(
      initMs: (json['init_ms'] as num?)?.toDouble() ?? 0,
      predictMs: (json['predict_ms'] as num?)?.toDouble() ?? 0,
      decodeMs: (json['decode_ms'] as num?)?.toDouble() ?? 0,
      resizeMs: (json['resize_ms'] as num?)?.toDouble() ?? 0,
      detMs: (json['det_ms'] as num?)?.toDouble() ?? 0,
      recMs: (json['rec_ms'] as num?)?.toDouble() ?? 0,
      postMs: (json['post_ms'] as num?)?.toDouble() ?? 0,
      mnnConfiguredBackend: json['mnn_configured_backend']?.toString(),
      mnnSessionBackends: rawBackends is List
          ? rawBackends.map((e) => e.toString()).toList(growable: false)
          : const [],
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

class OcrRecognizePhasedResult {
  const OcrRecognizePhasedResult({
    required this.result,
    required this.ffiMs,
    required this.parseMs,
  });

  final OcrRecognizeResult result;
  final int ffiMs;
  final int parseMs;
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
    return recognizePhased(imageBytes).result;
  }

  OcrRecognizePhasedResult recognizePhased(Uint8List imageBytes) {
    _assertNotDisposed();
    final ffiStopwatch = Stopwatch()..start();
    final jsonText = nativeBindings.ocrRecognizeTimed(
      engine: _handle,
      imageBytes: imageBytes,
    );
    final ffiMs = ffiStopwatch.elapsedMilliseconds;
    final parseStopwatch = Stopwatch()..start();
    final result = OcrRecognizeResult.fromJson(
      (jsonDecode(jsonText) as Map).cast<String, dynamic>(),
    );
    final parseMs = parseStopwatch.elapsedMilliseconds;
    return OcrRecognizePhasedResult(
      result: result,
      ffiMs: ffiMs,
      parseMs: parseMs,
    );
  }

  Future<OcrRecognizeResult> recognizeRgbTimed({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    return recognizeRgbPhased(
      rgbBytes: rgbBytes,
      width: width,
      height: height,
    ).result;
  }

  OcrRecognizePhasedResult recognizeRgbPhased({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) {
    _assertNotDisposed();
    final ffiStopwatch = Stopwatch()..start();
    final jsonText = nativeBindings.ocrRecognizeRgbTimed(
      engine: _handle,
      rgbBytes: rgbBytes,
      width: width,
      height: height,
    );
    final ffiMs = ffiStopwatch.elapsedMilliseconds;
    final parseStopwatch = Stopwatch()..start();
    final result = OcrRecognizeResult.fromJson(
      (jsonDecode(jsonText) as Map).cast<String, dynamic>(),
    );
    final parseMs = parseStopwatch.elapsedMilliseconds;
    return OcrRecognizePhasedResult(
      result: result,
      ffiMs: ffiMs,
      parseMs: parseMs,
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

  Future<String> plainText(
    Uint8List imageBytes, {
    double? minConfidence,
    int? maxSide,
  }) async {
    final session = await openSession(
      minConfidence: minConfidence,
      maxSide: maxSide,
    );
    try {
      return session.plainText(imageBytes);
    } finally {
      session.dispose();
    }
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
