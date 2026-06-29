import 'dart:io';

/// GitHub Release defaults for local-infer-core model packs and native libs.
class PackRelease {
  PackRelease({
    required this.releaseRepo,
    required this.releaseTag,
  });

  static const defaultRepo = 'SuiltaPico/local-infer-core';
  static const defaultTag = 'v0.1.0';

  final String releaseRepo;
  final String releaseTag;

  /// Defaults aligned with `pubspec.yaml` version / hooks `release_tag`.
  factory PackRelease.defaults() => PackRelease(
        releaseRepo: defaultRepo,
        releaseTag: defaultTag,
      );

  static String normalizeTag(String tag) =>
      tag.startsWith('v') ? tag : 'v$tag';

  /// `https://github.com/{repo}/releases/download/{tag}/{packId}.zip`
  String packDownloadUrl(String packId) {
    final vTag = normalizeTag(releaseTag);
    return 'https://github.com/$releaseRepo/releases/download/$vTag/$packId.zip';
  }
}

/// Read release repo/tag from `pubspec.yaml` (version → `v{version}`).
({String repo, String tag}) readReleaseDefaults(Uri packageRoot) {
  final pubspecFile = File.fromUri(packageRoot.resolve('pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return (repo: PackRelease.defaultRepo, tag: PackRelease.defaultTag);
  }

  final text = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(r'^version:\s*([^\s#]+)', multiLine: true)
      .firstMatch(text);
  final version = versionMatch?.group(1)?.trim() ?? '0.1.0';
  return (
    repo: PackRelease.defaultRepo,
    tag: PackRelease.normalizeTag(version),
  );
}
