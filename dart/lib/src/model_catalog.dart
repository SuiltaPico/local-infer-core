import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'exceptions.dart';

/// Default OCR pack for desktop (Windows / Linux / macOS ONNX).
const String defaultOcrPackId = 'ocr.paddle.ppocr6-tiny.onnx.fp32';

/// Environment variable pointing at a directory containing pack subfolders.
const String localInferModelsDirEnv = 'LOCAL_INFER_MODELS_DIR';

abstract final class ModelCatalog {
  ModelCatalog._();

  static Future<void> ensureDefaults({
    required String modelsDir,
    List<String> packIds = const [defaultOcrPackId],
  }) async {
    final dir = Directory(modelsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    for (final packId in packIds) {
      if (await isPackInstalled(modelsDir, packId)) {
        continue;
      }

      final envModels = Platform.environment[localInferModelsDirEnv];
      if (envModels != null && envModels.isNotEmpty) {
        final source = p.join(envModels, packId);
        if (await Directory(source).exists()) {
          await installFromDirectory(
            modelsDir: modelsDir,
            sourceDir: source,
            packId: packId,
          );
          continue;
        }
      }

      final bundled = await _tryLoadBundledPackZip(packId);
      if (bundled != null) {
        await installFromZipBytes(
          modelsDir: modelsDir,
          zipBytes: bundled,
          expectedPackId: packId,
        );
        continue;
      }

      throw LocalInferException(
        '模型包 $packId 未安装。\n'
        '请将官方 zip 解压到 $modelsDir/$packId/，'
        '或设置 $localInferModelsDirEnv，'
        '或在 local_infer_core assets 中提供 bundled zip。',
      );
    }
  }

  static Future<bool> isPackInstalled(String modelsDir, String packId) async {
    final manifest = File(p.join(modelsDir, packId, 'manifest.json'));
    return manifest.exists();
  }

  static Future<void> installFromDirectory({
    required String modelsDir,
    required String sourceDir,
    required String packId,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw LocalInferException('源目录不存在: $sourceDir');
    }
    final manifest = File(p.join(sourceDir, 'manifest.json'));
    if (!await manifest.exists()) {
      throw LocalInferException('源目录缺少 manifest.json: $sourceDir');
    }

    final dest = Directory(p.join(modelsDir, packId));
    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }
    await dest.create(recursive: true);

    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: sourceDir);
      final outFile = File(p.join(dest.path, relative));
      await outFile.parent.create(recursive: true);
      await entity.copy(outFile.path);
    }
  }

  static Future<void> installFromZipBytes({
    required String modelsDir,
    String? expectedPackId,
    required List<int> zipBytes,
    String? expectedSha256,
  }) async {
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = sha256.convert(zipBytes).toString();
      if (digest != expectedSha256.toLowerCase()) {
        throw LocalInferException(
          '模型包 sha256 不匹配: expected $expectedSha256, got $digest',
        );
      }
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final rootPrefix = expectedPackId == null
        ? null
        : '$expectedPackId/';

    for (final file in archive) {
      if (!file.isFile) continue;
      var name = file.name.replaceAll('\\', '/');
      if (rootPrefix != null) {
        if (!name.startsWith(rootPrefix)) continue;
        name = name.substring(rootPrefix.length);
      }
      if (name.isEmpty) continue;
      final out = File(p.join(modelsDir, expectedPackId ?? '', name));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>);
    }

    if (expectedPackId != null &&
        !await isPackInstalled(modelsDir, expectedPackId)) {
      throw LocalInferException(
        '解压后未找到 manifest: ${p.join(modelsDir, expectedPackId, 'manifest.json')}',
      );
    }
  }

  static Future<List<int>?> _tryLoadBundledPackZip(String packId) async {
    final assetPath = 'assets/packs/$packId.zip';
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }

  static Future<Map<String, dynamic>> readCatalogJson() async {
    try {
      final raw = await rootBundle.loadString('assets/catalog.json');
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return const {'packs': []};
    }
  }
}
