import 'dart:convert';

import 'ffi_bindings.dart';

/// Runtime execution-provider / MNN backend availability from native library.
class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.backend,
    required this.available,
  });

  final String backend;
  final Set<String> available;

  factory RuntimeCapabilities.fromJson(Map<String, dynamic> json) {
    final raw = json['available'];
    return RuntimeCapabilities(
      backend: json['backend']?.toString() ?? 'onnx',
      available: raw is List
          ? raw.map((e) => e.toString()).toSet()
          : const {'cpu'},
    );
  }

  /// Query [infer_runtime_backends_json] from the loaded native library.
  ///
  /// Returns null when the symbol is missing (older `infer_core` build).
  static RuntimeCapabilities? tryLoad() {
    final jsonText = nativeBindings.runtimeBackendsJson();
    if (jsonText == null) return null;
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return RuntimeCapabilities.fromJson(decoded);
  }
}
