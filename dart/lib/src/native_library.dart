import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Environment variable for an explicit native library path (CI / local dev).
const String localInferCoreLibEnv = 'LOCAL_INFER_CORE_LIB';

/// Bundled native asset id (see `hook/build.dart`).
const String nativeAssetId = 'package:local_infer_core/src/native_library.dart';

DynamicLibrary openLocalInferCoreLibrary() {
  final override = Platform.environment[localInferCoreLibEnv];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('libinfer_core.so');
  }

  if (_tryOpenBundledLibrary() case final lib?) {
    return lib;
  }

  final path = resolveNativeLibraryPath();
  if (!File(path).existsSync()) {
    throw StateError(
      'local_infer_core native library not found at:\n  $path\n'
      'Run `dart pub get` (build hook), `cargo build -p infer-core-ffi --release`, '
      'or set $localInferCoreLibEnv.',
    );
  }
  return DynamicLibrary.open(path);
}

DynamicLibrary? _tryOpenBundledLibrary() {
  try {
    _inferCoreVersionSymbol();
    final lib = DynamicLibrary.process();
    if (lib.providesSymbol('infer_core_version')) {
      return lib;
    }
  } on Object {
    // No bundled asset for this target.
  }
  return null;
}

@Native<Pointer<Utf8> Function()>(
  assetId: nativeAssetId,
  symbol: 'infer_core_version',
  isLeaf: true,
)
external Pointer<Utf8> _inferCoreVersionSymbol();

String resolveNativeLibraryPath() {
  if (Platform.isAndroid) {
    return 'libinfer_core.so';
  }

  final packageRoot = _packageRoot();
  if (Platform.isWindows) {
    return p.join(
      packageRoot,
      'native',
      'windows',
      _windowsArch(),
      'lib',
      'infer_core.dll',
    );
  }
  if (Platform.isLinux) {
    return p.join(
      packageRoot,
      'native',
      'linux',
      _linuxArch(),
      'lib',
      'libinfer_core.so',
    );
  }
  if (Platform.isMacOS) {
    return p.join(
      packageRoot,
      'native',
      'macos',
      _macosArch(),
      'lib',
      'libinfer_core.dylib',
    );
  }
  throw UnsupportedError(
    'local_infer_core: unsupported platform ${Platform.operatingSystem}',
  );
}

String _packageRoot() {
  final fromConfig = _packageRootFromPackageConfig();
  if (fromConfig != null) {
    return fromConfig;
  }

  final fromCwd = _packageRootFromCwdPubspec();
  if (fromCwd != null) {
    return fromCwd;
  }

  throw StateError(
    'local_infer_core: cannot locate package root; run from a project with '
    'local_infer_core in pubspec, or set $localInferCoreLibEnv',
  );
}

String? _packageRootFromPackageConfig() {
  final explicit = Platform.packageConfig;
  if (explicit != null) {
    final root = _localInferCoreRootFromConfig(File(explicit));
    if (root != null) {
      return root;
    }
  }

  var dir = Directory.current;
  while (true) {
    final configFile = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (configFile.existsSync()) {
      final root = _localInferCoreRootFromConfig(configFile);
      if (root != null) {
        return root;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}

String? _localInferCoreRootFromConfig(File configFile) {
  try {
    final json =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final packages = json['packages'] as List<dynamic>?;
    if (packages == null) {
      return null;
    }
    for (final pkg in packages) {
      final map = pkg as Map<String, dynamic>;
      if (map['name'] != 'local_infer_core') {
        continue;
      }
      final rootUri = map['rootUri'] as String;
      final configDir = p.dirname(configFile.path);
      final root = rootUri.startsWith('file:')
          ? p.fromUri(Uri.parse(rootUri))
          : p.normalize(p.join(configDir, rootUri));
      if (_isPackageRoot(root)) {
        return root;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

String? _packageRootFromCwdPubspec() {
  var dir = Directory.current;
  while (true) {
    if (_isPackageRoot(dir.path)) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}

bool _isPackageRoot(String dir) {
  final pubspec = File(p.join(dir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    return false;
  }
  return pubspec.readAsStringSync().contains('name: local_infer_core');
}

String _windowsArch() =>
    Platform.version.contains('arm64') ? 'arm64' : 'x64';

String _linuxArch() {
  if (Platform.version.contains('arm64') ||
      Platform.version.contains('aarch64')) {
    return 'arm64';
  }
  return 'x64';
}

String _macosArch() =>
    Platform.version.contains('arm64') ? 'arm64' : 'x64';
