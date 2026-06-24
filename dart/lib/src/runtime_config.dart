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

class RuntimeConfig {
  const RuntimeConfig({this.onnx});

  final OnnxConfig? onnx;

  factory RuntimeConfig.auto() => const RuntimeConfig(
        onnx: OnnxConfig(executionProviders: ['auto']),
      );

  factory RuntimeConfig.cpu() => const RuntimeConfig(
        onnx: OnnxConfig(executionProviders: ['cpu']),
      );

  Map<String, dynamic> toJson() => {
        if (onnx != null) 'onnx': onnx!.toJson(),
      };

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final onnxJson = json['onnx'];
    return RuntimeConfig(
      onnx: onnxJson is Map<String, dynamic>
          ? OnnxConfig.fromJson(onnxJson)
          : null,
    );
  }
}
