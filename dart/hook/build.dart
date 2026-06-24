import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:local_infer_core/src/native_release.dart';
import 'package:local_infer_core/src/native_release_fetch.dart';

const String nativeAssetName = 'src/native_library.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final targetOS = code.targetOS;
    final targetArchitecture = code.targetArchitecture;

    if (input.userDefines['skip_download'] == true) {
      return;
    }

    final repo =
        input.userDefines['release_repo'] as String? ?? defaultReleaseRepo;
    final tag =
        input.userDefines['release_tag'] as String? ?? defaultReleaseTag;
    final localLibUri = input.userDefines.path('local_lib');

    try {
      final libFile = await resolveNativeLibraryFile(
        outputDirectory: Directory.fromUri(input.outputDirectoryShared),
        packageRoot: input.packageRoot,
        targetOS: targetOS,
        targetArchitecture: targetArchitecture,
        repo: repo,
        tag: tag,
        localLib: localLibUri?.toFilePath(),
      );

      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: nativeAssetName,
          linkMode: DynamicLoadingBundled(),
          file: libFile.uri,
        ),
      );

      if (Platform.isLinux || Platform.isMacOS) {
        output.dependencies.add(libFile.uri);
      }
    } on UnsupportedError catch (e) {
      throw UnsupportedError(
        'local_infer_core: ${e.message ?? e}\n'
        'Supported: Windows (x64, arm64). Use hooks user_defines local_lib, '
        'LOCAL_INFER_CORE_LIB, or cargo build -p infer-core-ffi --release.',
      );
    } on HttpException catch (e) {
      throw StateError(
        'local_infer_core: failed to download native library (${e.uri}): ${e.message}\n'
        'Build locally: cargo build -p infer-core-ffi --release\n'
        'Or set hooks user_defines local_lib / LOCAL_INFER_CORE_LIB.',
      );
    }
  });
}
