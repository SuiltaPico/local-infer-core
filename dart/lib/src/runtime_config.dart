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

class RuntimeConfig {
  const RuntimeConfig({this.onnx, this.mnn});

  final OnnxConfig? onnx;
  final MnnConfig? mnn;

  factory RuntimeConfig.auto() {
    if (Platform.isAndroid) {
      return const RuntimeConfig(
        mnn: MnnConfig(backend: 'vulkan'),
      );
    }
    return const RuntimeConfig(
      onnx: OnnxConfig(executionProviders: ['auto']),
    );
  }

  factory RuntimeConfig.cpu() => const RuntimeConfig(
        onnx: OnnxConfig(executionProviders: ['cpu']),
      );

  Map<String, dynamic> toJson() => {
        if (onnx != null) 'onnx': onnx!.toJson(),
        if (mnn != null) 'mnn': mnn!.toJson(),
      };

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final onnxJson = json['onnx'];
    final mnnJson = json['mnn'];
    return RuntimeConfig(
      onnx: onnxJson is Map<String, dynamic>
          ? OnnxConfig.fromJson(onnxJson)
          : null,
      mnn: mnnJson is Map<String, dynamic> ? MnnConfig.fromJson(mnnJson) : null,
    );
  }
}
