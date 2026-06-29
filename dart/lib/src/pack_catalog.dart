import 'dart:convert';

import 'package:flutter/services.dart';

const String packCatalogAssetPath = 'packages/local_infer_core/assets/catalog.json';

/// Official model pack entry from `assets/catalog.json`.
class PackCatalogEntry {
  PackCatalogEntry({
    required this.id,
    required this.sizeBytes,
    required this.sha256,
    required this.urls,
  });

  factory PackCatalogEntry.fromJson(Map<String, dynamic> json) {
    return PackCatalogEntry(
      id: json['id'] as String,
      sizeBytes: json['size_bytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      urls: (json['urls'] as List<dynamic>? ?? const [])
          .map((url) => url as String)
          .toList(growable: false),
    );
  }

  final String id;
  final int sizeBytes;
  final String sha256;
  final List<String> urls;
}

/// Official Release metadata + pack list shipped with the Flutter plugin.
class PackCatalog {
  PackCatalog({
    required this.releaseRepo,
    required this.releaseTag,
    required this.packs,
  });

  factory PackCatalog.fromJson(Map<String, dynamic> json) {
    final release = json['release'] as Map<String, dynamic>? ?? const {};
    return PackCatalog(
      releaseRepo: release['repo'] as String? ?? '',
      releaseTag: release['tag'] as String? ?? '',
      packs: (json['packs'] as List<dynamic>? ?? const [])
          .map(
            (entry) => PackCatalogEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  /// Parse catalog JSON (UTF-8, no BOM).
  factory PackCatalog.parse(String jsonText) {
    final trimmed = jsonText.startsWith('\uFEFF')
        ? jsonText.substring(1)
        : jsonText;
    return PackCatalog.fromJson(
      jsonDecode(trimmed) as Map<String, dynamic>,
    );
  }

  /// Load bundled catalog via Flutter [AssetBundle].
  static Future<PackCatalog> loadFromAssetBundle([AssetBundle? bundle]) async {
    final resolved = bundle ?? rootBundle;
    final jsonText = await resolved.loadString(packCatalogAssetPath);
    return PackCatalog.parse(jsonText);
  }

  final String releaseRepo;
  final String releaseTag;
  final List<PackCatalogEntry> packs;

  PackCatalogEntry? findPack(String id) {
    for (final pack in packs) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }
}
