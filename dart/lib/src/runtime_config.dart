import 'dart:io';

class OnnxConfig {
  const OnnxConfig({
    this.executionProviders = const ['auto'],
    this.intraThreads,
    this.interThreads,
    this.appendCpuFallback = true,
    this.gpuSingleSession = true,
  });

  final List<String> executionProviders;
  final int? intraThreads;
  final int? interThreads;
  final bool appendCpuFallback;
  final bool gpuSingleSession;

  Map<String, dynamic> toJson() => {
        'execution_providers': executionProviders,
        if (intraThreads != null) 'intra_threads': intraThreads,
        if (interThreads != null) 'inter_threads': interThreads,
        'append_cpu_fallback': appendCpuFallback,
        'gpu_single_session': gpuSingleSession,
      };

  factory OnnxConfig.fromJson(Map<String, dynamic> json) {
    return OnnxConfig(
      executionProviders: (json['execution_providers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const ['auto'],
      intraThreads: json['intra_threads'] as int?,
      interThreads: json['inter_threads'] as int?,
      appendCpuFallback: json['append_cpu_fallback'] as bool? ?? true,
      gpuSingleSession: json['gpu_single_session'] as bool? ?? true,
    );
  }
}

class MnnConfig {
  const MnnConfig({
    this.backend = 'cpu',
    this.numThread,
    this.precision = 'normal',
  });

  final String backend;
  final int? numThread;
  final String precision;

  Map<String, dynamic> toJson() => {
        'backend': backend,
        if (numThread != null) 'num_thread': numThread,
        'precision': precision,
      };

  factory MnnConfig.fromJson(Map<String, dynamic> json) {
    return MnnConfig(
      backend: json['backend']?.toString() ?? 'cpu',
      numThread: json['num_thread'] as int?,
      precision: json['precision']?.toString() ?? 'normal',
    );
  }
}

/// OCR rec / icon embed batch sizes (native clamps to 1–32).
class BatchConfig {
  const BatchConfig({
    this.ocrRec = defaultOcrRecBatch,
    this.embed = defaultEmbedBatch,
    this.ocrRecStrategy = OcrRecStrategy.none,
  });

  static const defaultOcrRecBatch = 8;
  static const defaultEmbedBatch = 8;
  static const minBatch = 1;
  static const maxBatch = 32;

  final int ocrRec;
  final int embed;
  final OcrRecStrategy ocrRecStrategy;

  int get clampedOcrRec => ocrRec.clamp(minBatch, maxBatch);
  int get clampedEmbed => embed.clamp(minBatch, maxBatch);

  Map<String, dynamic> toJson() => {
        'ocr_rec': ocrRec,
        'embed': embed,
        'ocr_rec_strategy': ocrRecStrategy.name,
      };

  factory BatchConfig.fromJson(Map<String, dynamic> json) {
    return BatchConfig(
      ocrRec: _readBatch(json['ocr_rec'], defaultOcrRecBatch),
      embed: _readBatch(json['embed'], defaultEmbedBatch),
      ocrRecStrategy: OcrRecStrategy.fromStored(
          json['ocr_rec_strategy']?.toString()),
    );
  }

  BatchConfig copyWith({
    int? ocrRec,
    int? embed,
    OcrRecStrategy? ocrRecStrategy,
  }) {
    return BatchConfig(
      ocrRec: ocrRec ?? this.ocrRec,
      embed: embed ?? this.embed,
      ocrRecStrategy: ocrRecStrategy ?? this.ocrRecStrategy,
    );
  }
}

enum OcrRecStrategy {
  none,
  bucketing,
  unified;

  static OcrRecStrategy fromStored(String? value) {
    switch (value) {
      case 'bucketing':
        return OcrRecStrategy.bucketing;
      case 'unified':
        return OcrRecStrategy.unified;
      case 'none':
      default:
        return OcrRecStrategy.none;
    }
  }
}

int _readBatch(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

class RuntimeConfig {
  const RuntimeConfig({this.onnx, this.mnn, this.batch = const BatchConfig()});

  final OnnxConfig? onnx;
  final MnnConfig? mnn;
  final BatchConfig batch;

  factory RuntimeConfig.auto({BatchConfig batch = const BatchConfig()}) {
    if (Platform.isAndroid) {
      return RuntimeConfig(
        mnn: const MnnConfig(backend: 'vulkan'),
        batch: batch,
      );
    }
    return RuntimeConfig(
      onnx: const OnnxConfig(executionProviders: ['auto']),
      batch: batch,
    );
  }

  factory RuntimeConfig.cpu({BatchConfig batch = const BatchConfig()}) =>
      RuntimeConfig(
        onnx: const OnnxConfig(executionProviders: ['cpu']),
        batch: batch,
      );

  Map<String, dynamic> toJson() => {
        if (onnx != null) 'onnx': onnx!.toJson(),
        if (mnn != null) 'mnn': mnn!.toJson(),
        'batch': batch.toJson(),
      };

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final onnxJson = json['onnx'];
    final mnnJson = json['mnn'];
    final batchJson = json['batch'];
    return RuntimeConfig(
      onnx: onnxJson is Map<String, dynamic>
          ? OnnxConfig.fromJson(onnxJson)
          : null,
      mnn: mnnJson is Map<String, dynamic> ? MnnConfig.fromJson(mnnJson) : null,
      batch: batchJson is Map<String, dynamic>
          ? BatchConfig.fromJson(batchJson)
          : const BatchConfig(),
    );
  }

  RuntimeConfig copyWith({
    OnnxConfig? onnx,
    MnnConfig? mnn,
    BatchConfig? batch,
  }) {
    return RuntimeConfig(
      onnx: onnx ?? this.onnx,
      mnn: mnn ?? this.mnn,
      batch: batch ?? this.batch,
    );
  }

  /// Client-side fallback when native status API is unavailable.
  String resolvedMnnBackend(Set<String> availableBackends) {
    final configured = mnn?.backend ?? 'cpu';
    if (configured != 'auto') return configured;
    for (final name in ['vulkan', 'opencl', 'metal', 'cuda']) {
      if (availableBackends.contains(name)) return name;
    }
    return 'cpu';
  }
}
