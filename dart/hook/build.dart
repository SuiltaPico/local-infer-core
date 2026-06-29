import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'release_config.dart';
import 'native_release_fetch.dart';
import 'supported_target.dart';

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

    if (!isBundledNativeTargetSupported(targetOS, targetArchitecture)) {
      return;
    }

    final defaults = readReleaseDefaults(input.packageRoot);
    final repo =
        input.userDefines['release_repo'] as String? ?? defaults.repo;
    final tag = input.userDefines['release_tag'] as String? ?? defaults.tag;
    final localLibUri = input.userDefines.path('local_lib');

    try {
      final libFile = await resolveNativeLibraryFile(
        outputDirectory: Directory.fromUri(input.outputDirectoryShared),
        targetOS: targetOS,
        targetArchitecture: targetArchitecture,
        repo: repo,
        tag: tag,
        localLib: localLibUri?.toFilePath(),
      );

      registerBundledNativeCodeAssets(
        addAsset: output.assets.code.add,
        packageName: input.packageName,
        primaryAssetName: nativeAssetName,
        primaryLib: libFile,
        targetOS: targetOS,
      );

      if (Platform.isLinux || Platform.isMacOS) {
        output.dependencies.add(libFile.uri);
      }
    } on UnsupportedError catch (e) {
      throw UnsupportedError(
        'local_infer_core: ${e.message ?? e}\n'
        'Supported: Windows (x64, arm64), Android (arm64, x64).\n'
        'Set hooks.user_defines.local_infer_core.local_lib to a built '
        'infer_core binary, or ensure GitHub Release assets exist.',
      );
    } on HttpException catch (e) {
      throw StateError(
        'local_infer_core: failed to download native library (${e.uri}): ${e.message}\n'
        'Build locally and set hooks.user_defines.local_infer_core.local_lib, '
        'or fix network/proxy access to GitHub Releases.',
      );
    }
  });
}
