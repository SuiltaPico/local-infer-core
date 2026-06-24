import 'package:code_assets/code_assets.dart';

const String defaultReleaseRepo = 'SuiltaPico/local-infer-core';
const String defaultReleaseTag = '0.1.0';

String nativeAssetBaseName({
  required OS targetOS,
  required Architecture targetArchitecture,
}) {
  if (targetOS == OS.android) {
    final abi = androidJniAbi(targetArchitecture);
    return 'infer-core-android-$abi';
  }
  final platform = switch (targetOS) {
    OS.linux => 'linux',
    OS.macOS => 'macos',
    OS.windows => 'windows',
    _ => throw UnsupportedError('unsupported target OS: ${targetOS.name}'),
  };
  final arch = switch (targetArchitecture) {
    Architecture.x64 => 'x86_64',
    Architecture.arm64 => 'aarch64',
    _ => throw UnsupportedError(
        'unsupported desktop architecture: ${targetArchitecture.name}',
      ),
  };
  return 'infer-core-$platform-$arch';
}

String androidJniAbi(Architecture architecture) => switch (architecture) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.arm => 'armeabi-v7a',
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError(
          'unsupported Android architecture: ${architecture.name}',
        ),
    };

String bundledLibraryBaseName(OS targetOS) => 'infer_core';

String desktopLibraryRelativePath({
  required OS targetOS,
  required Architecture targetArchitecture,
}) {
  final platform = switch (targetOS) {
    OS.linux => 'linux',
    OS.macOS => 'macos',
    OS.windows => 'windows',
    _ => throw UnsupportedError('unsupported target OS: ${targetOS.name}'),
  };
  final archFolder = switch (targetArchitecture) {
    Architecture.x64 => 'x64',
    Architecture.arm64 => 'arm64',
    _ => throw UnsupportedError(
        'unsupported desktop architecture: ${targetArchitecture.name}',
      ),
  };
  final fileName = targetOS.dylibFileName(bundledLibraryBaseName(targetOS));
  return 'native/$platform/$archFolder/lib/$fileName';
}

String androidLibraryRelativePath(Architecture targetArchitecture) {
  final abi = androidJniAbi(targetArchitecture);
  return 'jniLibs/$abi/libinfer_core.so';
}

Uri releaseArchiveUrl({
  required String repo,
  required String tag,
  required String assetBaseName,
  required OS targetOS,
}) {
  final vTag = tag.startsWith('v') ? tag : 'v$tag';
  final ext = targetOS == OS.windows ? 'zip' : 'tar.gz';
  return Uri.https(
    'github.com',
    '/$repo/releases/download/$vTag/$assetBaseName.$ext',
  );
}

String? preinstalledLibraryRelativePath({
  required OS targetOS,
  required Architecture targetArchitecture,
}) {
  try {
    if (targetOS == OS.android) {
      return androidLibraryRelativePath(targetArchitecture);
    }
    return desktopLibraryRelativePath(
      targetOS: targetOS,
      targetArchitecture: targetArchitecture,
    );
  } on UnsupportedError {
    return null;
  }
}
