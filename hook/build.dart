import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'native_binary.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final configFile = input.packageRoot.resolve('hook/native_config.json');
    final config =
        jsonDecode(await File.fromUri(configFile).readAsString())
            as Map<String, dynamic>;
    output.dependencies.add(configFile);
    final mode = input.userDefines['native_build'] ?? 'binary';
    if (!['binary', 'auto', 'source', 'system'].contains(mode)) {
      throw FormatException(
        'Invalid native_build: $mode. Use binary, auto, source, or system.',
      );
    }
    final code = input.config.code;
    final libraryName = switch (code.targetOS) {
      OS.windows => 'duckdb.dll',
      OS.macOS || OS.iOS => 'libduckdb.dylib',
      OS.linux || OS.android => 'libduckdb.so',
      final os => throw UnsupportedError('DuckDB does not support $os.'),
    };
    final localPath = input.userDefines['library_path'];
    if (localPath != null && localPath is! String) {
      throw const FormatException(
        'library_path must be an absolute file path.',
      );
    }
    if (localPath != null && mode == 'system') {
      throw const FormatException(
        'Use library_path with binary mode, not system mode.',
      );
    }
    if (mode == 'system') {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'duckdb',
          linkMode: DynamicLoadingSystem(Uri.file(libraryName)),
        ),
      );
      return;
    }
    final target = binaryTarget(
      code.targetOS,
      code.targetArchitecture,
      simulator:
          code.targetOS == OS.iOS &&
          code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
      linuxLibc: input.userDefines['linux_libc'] ?? 'glibc',
    );
    File library;
    if (localPath is String) {
      library = File(localPath);
      if (!library.isAbsolute || !await library.exists()) {
        throw ArgumentError(
          'library_path must point to an existing absolute file: $localPath',
        );
      }
      output.dependencies.add(library.uri);
    } else if (mode == 'source') {
      final script = input.packageRoot.resolve('tools/build_native.py');
      output.dependencies.add(script);
      final directory = Directory.fromUri(
        input.outputDirectory.resolve('source/'),
      );
      final result =
          await Process.run(Platform.isWindows ? 'python' : 'python3', [
            File.fromUri(script).path,
            '--target',
            target,
            '--output',
            directory.path,
          ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'build_native.py',
          [target],
          '${result.stdout}\n${result.stderr}',
          result.exitCode,
        );
      }
      library = File('${directory.path}/$libraryName');
    } else {
      // auto intentionally uses the same reproducible binary selection. Never
      // silently start a source build when a release is missing or corrupt.
      library = await obtainBinary(
        config: config,
        target: target,
        libraryName: libraryName,
        cache: Directory.fromUri(
          input.outputDirectoryShared.resolve('binaries/'),
        ),
        repository: input.userDefines['binary_repository'] as String?,
      );
    }
    // Use one filename across architectures, particularly iOS device/simulator.
    final bundled = File.fromUri(input.outputDirectory.resolve(libraryName));
    await bundled.parent.create(recursive: true);
    await library.copy(bundled.path);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'duckdb',
        linkMode: DynamicLoadingBundled(),
        file: bundled.uri,
      ),
    );
  });
}
