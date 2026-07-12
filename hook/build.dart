import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _source = 'source';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final mode = input.userDefines['native_build'];
    if (mode != null && mode != _source && mode != 'auto' && mode != 'binary') {
      throw const FormatException(
        'hooks.user_defines.dart_duckdb.native_build must be '
        '"source", "binary", or "auto".',
      );
    }

    // Binary mode remains the default and is still handled by the existing
    // platform integration. The hook must not emit an asset in that mode or
    // the platform integration would package two DuckDB libraries.
    if (mode != _source) return;

    final config = input.config.code;
    if (config.targetOS != OS.android && config.targetOS != OS.iOS) return;
    final packageRoot = Directory.fromUri(input.packageRoot);
    final outputDirectory = Directory.fromUri(input.outputDirectory);
    await outputDirectory.create(recursive: true);

    final command = _buildCommand(config: config);
    final result = await Process.run(
      command.script,
      command.arguments,
      workingDirectory: packageRoot.path,
      runInShell: Platform.isWindows,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw ProcessException(
        command.script,
        command.arguments,
        'DuckDB source build failed (exit code ${result.exitCode}).',
        result.exitCode,
      );
    }

    final built = _builtLibrary(packageRoot, config, command.outputFileName);
    if (!built.existsSync()) {
      throw StateError('DuckDB source build did not produce ${built.path}.');
    }
    final outputFile = File(
      '${outputDirectory.path}/${command.outputFileName}',
    );
    await outputFile.parent.create(recursive: true);
    await built.copy(outputFile.path);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/ffi/load_library.dart',
        linkMode: DynamicLoadingBundled(),
        file: outputFile.uri,
      ),
    );
  });
}

({String script, List<String> arguments, String outputFileName}) _buildCommand({
  required CodeConfig config,
}) {
  final os = config.targetOS;
  final arch = config.targetArchitecture;
  if (os == OS.android) {
    final abi = switch (arch) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.arm => 'armeabi-v7a',
      _ => throw UnsupportedError('Android architecture $arch is unsupported.'),
    };
    return (
      script: 'make',
      arguments: ['-C', 'android', 'build_$abi'],
      outputFileName: 'libduckdb.so',
    );
  }
  if (os == OS.iOS) {
    final target = config.iOS.targetSdk == IOSSdk.iPhoneSimulator
        ? (arch == Architecture.x64 ? 'sim_x64' : 'sim_arm64')
        : 'device';
    return (
      script: 'make',
      arguments: ['-C', 'ios', target],
      outputFileName: 'duckdb',
    );
  }
  throw UnsupportedError('DuckDB source builds are unsupported on $os.');
}

File _builtLibrary(Directory root, CodeConfig config, String outputFileName) {
  final os = config.targetOS;
  if (os == OS.android) {
    final abi = config.targetArchitecture == Architecture.arm64
        ? 'arm64-v8a'
        : 'armeabi-v7a';
    return File('${root.path}/android/src/main/jniLibs/$abi/libduckdb.so');
  }
  if (os == OS.iOS) {
    return File('${root.path}/ios/Libraries/release/duckdb.framework/duckdb');
  }
  throw UnsupportedError('Unsupported target OS ${config.targetOS}.');
}
