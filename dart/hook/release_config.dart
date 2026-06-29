import 'dart:io';

const String defaultReleaseRepo = 'SuiltaPico/local-infer-core';
const String defaultReleaseTag = 'v0.1.0';

String normalizeReleaseTag(String tag) =>
    tag.startsWith('v') ? tag : 'v$tag';

/// Release repo/tag for native lib hook (`pubspec.yaml` version → `v{version}`).
({String repo, String tag}) readReleaseDefaults(Uri packageRoot) {
  final pubspecFile = File.fromUri(packageRoot.resolve('pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return (repo: defaultReleaseRepo, tag: defaultReleaseTag);
  }

  final text = pubspecFile.readAsStringSync();
  final versionMatch =
      RegExp(r'^version:\s*([^\s#]+)', multiLine: true).firstMatch(text);
  final version = versionMatch?.group(1)?.trim() ?? '0.1.0';
  return (
    repo: defaultReleaseRepo,
    tag: normalizeReleaseTag(version),
  );
}
