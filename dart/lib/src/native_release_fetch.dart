import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:local_infer_core/src/native_release.dart';
import 'package:path/path.dart' as p;

Future<File> fetchNativeLibrary({
  required Directory outputDirectory,
  required OS targetOS,
  required Architecture targetArchitecture,
  required String repo,
  required String tag,
}) async {
  final assetBase = nativeAssetBaseName(
    targetOS: targetOS,
    targetArchitecture: targetArchitecture,
  );
  final url = releaseArchiveUrl(
    repo: repo,
    tag: tag,
    assetBaseName: assetBase,
    targetOS: targetOS,
  );
  final ext = targetOS == OS.windows ? '.zip' : '.tar.gz';
  final archiveFile = File(p.join(outputDirectory.path, '$assetBase$ext'));
  final extractRoot = Directory(p.join(outputDirectory.path, assetBase));

  if (!await extractRoot.exists()) {
    await extractRoot.create(recursive: true);
  }

  if (!await archiveFile.exists()) {
    await _download(url, archiveFile);
    await _extractArchive(
      archiveFile: archiveFile,
      dest: extractRoot,
      isZip: targetOS == OS.windows,
    );
  }

  final libRelative = targetOS == OS.android
      ? androidLibraryRelativePath(targetArchitecture)
      : p.join(
          'lib',
          targetOS.dylibFileName(bundledLibraryBaseName(targetOS)),
        );

  final libFile = File(p.join(extractRoot.path, libRelative));
  if (!await libFile.exists()) {
    throw StateError(
      'expected library at ${libFile.path} after extracting $url',
    );
  }
  return libFile;
}

Future<void> _download(Uri url, File dest) async {
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'GET $url failed with status ${response.statusCode}',
        uri: url,
      );
    }
    await dest.parent.create(recursive: true);
    await response.pipe(dest.openWrite());
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractArchive({
  required File archiveFile,
  required Directory dest,
  required bool isZip,
}) async {
  if (isZip) {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        'Expand-Archive -LiteralPath "${archiveFile.path}" -DestinationPath "${dest.path}" -Force',
      ],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw StateError('Expand-Archive failed: ${result.stderr}');
    }
    return;
  }

  final result = await Process.run(
    'tar',
    ['-xzf', archiveFile.path, '-C', dest.path],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw StateError('tar extract failed: ${result.stderr}');
  }
}

Future<File> resolveNativeLibraryFile({
  required Directory outputDirectory,
  required Uri packageRoot,
  required OS targetOS,
  required Architecture targetArchitecture,
  required String repo,
  required String tag,
  String? localLib,
}) async {
  if (localLib != null && localLib.isNotEmpty) {
    final file = File(localLib);
    if (!await file.exists()) {
      throw StateError('local_lib not found: $localLib');
    }
    return file;
  }

  final envLib = Platform.environment['LOCAL_INFER_CORE_LIB'];
  if (envLib != null && envLib.isNotEmpty) {
    final file = File(envLib);
    if (!await file.exists()) {
      throw StateError('LOCAL_INFER_CORE_LIB not found: $envLib');
    }
    return file;
  }

  final preinstalledRelative = preinstalledLibraryRelativePath(
    targetOS: targetOS,
    targetArchitecture: targetArchitecture,
  );
  if (preinstalledRelative != null) {
    final preinstalled = File(
      p.join(packageRoot.toFilePath(), preinstalledRelative),
    );
    if (await preinstalled.exists()) {
      return preinstalled;
    }
  }

  final cargoOut = _cargoReleaseLibrary(packageRoot.toFilePath(), targetOS);
  if (cargoOut != null && await File(cargoOut).exists()) {
    return File(cargoOut);
  }

  return fetchNativeLibrary(
    outputDirectory: outputDirectory,
    targetOS: targetOS,
    targetArchitecture: targetArchitecture,
    repo: repo,
    tag: tag,
  );
}

String? _cargoReleaseLibrary(String packageRoot, OS targetOS) {
  final repoRoot = p.normalize(p.join(packageRoot, '..'));
  final fileName = targetOS.dylibFileName(bundledLibraryBaseName(targetOS));
  return p.join(repoRoot, 'target', 'release', fileName);
}
