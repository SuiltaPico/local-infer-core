import 'dart:convert';
import 'dart:io';

/// Release repo/tag defaults from `assets/catalog.json` (single source of truth).
({String repo, String tag}) readCatalogReleaseDefaults(Uri packageRoot) {
  final catalogFile = File.fromUri(
    packageRoot.resolve('assets/catalog.json'),
  );
  if (!catalogFile.existsSync()) {
    throw StateError(
      'local_infer_core: missing ${catalogFile.path} (release defaults)',
    );
  }

  final raw = catalogFile.readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final release = json['release'] as Map<String, dynamic>?;
  if (release == null) {
    throw StateError(
      'local_infer_core: assets/catalog.json missing "release" section',
    );
  }

  final repo = release['repo'] as String?;
  final tag = release['tag'] as String?;
  if (repo == null || repo.isEmpty || tag == null || tag.isEmpty) {
    throw StateError(
      'local_infer_core: assets/catalog.json release.repo/tag must be non-empty',
    );
  }

  return (repo: repo, tag: tag);
}
