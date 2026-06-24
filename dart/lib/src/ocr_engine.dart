import 'dart:typed_data';

import 'ffi_bindings.dart';
import 'registry.dart';

class LocalOcrEngine {
  const LocalOcrEngine({
    required this.registry,
    required this.packId,
  });

  final LocalInferRegistry registry;
  final String packId;

  Future<String> plainText(Uint8List imageBytes) async {
    return nativeBindings.ocrPlainText(
      registry: registry.nativeHandle,
      packId: packId,
      imageBytes: imageBytes,
    );
  }
}
