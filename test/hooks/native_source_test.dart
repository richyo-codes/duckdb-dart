import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/native_source.dart';

void main() {
  late Directory output;
  late List<List<String>> commands;
  const config = {'duckdb_version': 'v2.0.0', 'duckdb_commit': 'pinned'};
  setUp(() async {
    output = await Directory.systemTemp.createTemp('duckdb-source-test-');
    commands = [];
  });
  tearDown(() => output.delete(recursive: true));
  Future<String> run(String executable, List<String> args) async {
    commands.add([executable, ...args]);
    if (args.contains('rev-parse')) return 'pinned\n';
    if (args.contains('--build')) {
      for (final name in ['libduckdb.so', 'libduckdb.dylib']) {
        final library = File('${output.path}/build/src/$name');
        await library.parent.create(recursive: true);
        await library.writeAsString('synthetic');
      }
    }
    return '';
  }

  for (final target in [
    'linux-x64',
    'linux-arm64',
    'android-x64',
    'android-arm64',
    'ios-arm64',
    'ios-simulator-arm64',
    'ios-simulator-x64',
  ]) {
    test('$target builds and packages with the correct toolchain', () async {
      final ios = target.startsWith('ios');
      final library = await buildNativeSource(
        config: config,
        target: target,
        output: output,
        run: run,
        hostOS: ios ? 'macos' : 'linux',
        hostAbi: target.replaceAll('-', '_'),
        environment: {'ANDROID_NDK_HOME': '/ndk'},
      );
      expect(await library.readAsString(), 'synthetic');
      final configure = commands.firstWhere((c) => c.contains('-S'));
      expect(
        configure,
        contains('-DBUILD_EXTENSIONS=core_functions;parquet;json;icu'),
      );
      if (target.startsWith('linux')) {
        expect(configure.any((c) => c.contains('ANDROID')), isFalse);
        expect(commands.last.first, 'strip');
      } else if (ios) {
        expect(
          configure,
          contains(
            '-DCMAKE_OSX_SYSROOT=${target.contains('simulator') ? 'iphonesimulator' : 'iphoneos'}',
          ),
        );
        expect(commands.last.first, 'xcrun');
      } else {
        expect(
          configure,
          contains(
            '-DANDROID_ABI=${target.endsWith('x64') ? 'x86_64' : 'arm64-v8a'}',
          ),
        );
        expect(
          commands.last.first,
          p.join(
            '/ndk',
            'toolchains',
            'llvm',
            'prebuilt',
            'linux-x86_64',
            'bin',
            'llvm-strip',
          ),
        );
      }
    });
  }
  test(
    'invalid hosts, targets, jobs and missing NDK fail before commands',
    () async {
      for (final target in [
        'linux-arm64',
        'linux-x64-musl',
        'ios-arm64',
        'android-arm64',
      ]) {
        await expectLater(
          buildNativeSource(
            config: config,
            target: target,
            output: output,
            run: run,
            hostOS: 'linux',
            hostAbi: 'linux-x64',
            environment: {},
          ),
          throwsA(anything),
        );
      }
      await expectLater(
        buildNativeSource(
          config: config,
          target: 'linux-x64',
          output: output,
          run: run,
          jobs: 0,
        ),
        throwsArgumentError,
      );
      expect(commands, isEmpty);
    },
  );
  test('pin mismatch prevents compilation', () async {
    await expectLater(
      buildNativeSource(
        config: {...config, 'duckdb_commit': 'wrong'},
        target: 'linux-x64',
        output: output,
        run: run,
        hostOS: 'linux',
        hostAbi: 'linux-x64',
      ),
      throwsStateError,
    );
    expect(commands.any((c) => c.first == 'cmake'), isFalse);
  });
  test('compiler failure stops packaging', () async {
    await expectLater(
      buildNativeSource(
        config: config,
        target: 'linux-x64',
        output: output,
        hostOS: 'linux',
        hostAbi: 'linux-x64',
        run: (exe, args) async {
          if (exe == 'cmake') {
            throw ProcessException(exe, args, 'synthetic compiler failure', 1);
          }
          return run(exe, args);
        },
      ),
      throwsA(isA<ProcessException>()),
    );
    expect(await File('${output.path}/libduckdb.so').exists(), isFalse);
  });
  test('command runner reports failing subprocess exit code', () async {
    await expectLater(
      runSourceCommand(Platform.resolvedExecutable, [
        '--invalid-duckdb-test-option',
      ]),
      throwsA(
        isA<ProcessException>().having(
          (e) => e.errorCode,
          'exit code',
          isNonZero,
        ),
      ),
    );
  });
}
