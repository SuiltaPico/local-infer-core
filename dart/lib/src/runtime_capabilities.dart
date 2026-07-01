import 'dart:convert';

import 'ffi_bindings.dart';
import 'runtime_config.dart';

/// Runtime execution-provider / MNN backend availability from native library.
class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.backend,
    required this.available,
    this.resolvedMnnBackend,
    this.resolvedEps,
  });

  final String backend;
  final Set<String> available;
  final String? resolvedMnnBackend;
  final List<String>? resolvedEps;

  factory RuntimeCapabilities.fromJson(Map<String, dynamic> json) {
    final raw = json['available'];
    final resolvedEpsRaw = json['resolved_eps'];
    return RuntimeCapabilities(
      backend: json['backend']?.toString() ?? 'onnx',
      available: raw is List
          ? raw.map((e) => e.toString()).toSet()
          : const {'cpu'},
      resolvedMnnBackend: json['resolved_mnn_backend']?.toString(),
      resolvedEps: resolvedEpsRaw is List
          ? resolvedEpsRaw.map((e) => e.toString()).toList(growable: false)
          : null,
    );
  }

  /// Query [infer_runtime_backends_json] from the loaded native library.
  ///
  /// Returns null when the symbol is missing (older `infer_core` build).
  static RuntimeCapabilities? tryLoad() {
    return tryLoadStatus(const RuntimeConfig());
  }

  /// Query [infer_runtime_status_json] for a specific [RuntimeConfig].
  static RuntimeCapabilities? tryLoadStatus(RuntimeConfig runtimeConfig) {
    final jsonText = nativeBindings.runtimeStatusJson(
      jsonEncode(runtimeConfig.toJson()),
    );
    if (jsonText != null) {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        return RuntimeCapabilities.fromJson(decoded);
      }
    }

    final legacy = nativeBindings.runtimeBackendsJson();
    if (legacy == null) return null;
    final decoded = jsonDecode(legacy);
    if (decoded is! Map<String, dynamic>) return null;
    return RuntimeCapabilities.fromJson(decoded);
  }
}
