import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef SourceCommand =
    Future<String> Function(String executable, List<String> arguments);

Future<String> runSourceCommand(
  String executable,
  List<String> arguments,
) async {
  stderr.writeln('DuckDB source: $executable ${arguments.join(' ')}');
  final process = await Process.start(executable, arguments);
  final captured = StringBuffer();
  final output = process.stdout.transform(utf8.decoder).forEach((text) {
    captured.write(text);
    stderr.write(text);
  });
  final errors = process.stderr.forEach(stderr.add);
  final code = await process.exitCode;
  await Future.wait([output, errors]);
  if (code != 0) {
    throw ProcessException(
      executable,
      arguments,
      'DuckDB source build failed',
      code,
    );
  }
  return captured.toString();
}

/// Shared source builder for the native asset hook and manual CLI builds.
Future<File> buildNativeSource({
  required Map<String, dynamic> config,
  required String target,
  required Directory output,
  int jobs = 2,
  SourceCommand run = runSourceCommand,
  String? hostOS,
  String? hostAbi,
  Map<String, String>? environment,
}) async {
  final os = hostOS ?? Platform.operatingSystem;
  final abi = (hostAbi ?? Abi.current().toString()).replaceAll('_', '-');
  final env = environment ?? Platform.environment;
  const targets = {
    'android-arm64',
    'android-x64',
    'ios-arm64',
    'ios-simulator-arm64',
    'ios-simulator-x64',
    'linux-x64',
    'linux-arm64',
  };
  if (!targets.contains(target)) {
    throw UnsupportedError('Unsupported source target: $target');
  }
  if (jobs < 1) throw ArgumentError.value(jobs, 'jobs', 'Must be positive');
  final ios = target.startsWith('ios-');
  final linux = target.startsWith('linux-');
  if (ios && os != 'macos') {
    throw UnsupportedError('iOS source builds require macOS and Xcode.');
  }
  if (linux && (os != 'linux' || abi != target)) {
    throw UnsupportedError(
      'Linux source builds require a matching native Linux host; use binary mode or library_path for cross-compilation.',
    );
  }
  final options = [
    '-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_UNITTESTS=OFF',
    '-DBUILD_SHELL=OFF',
    '-DEXPORT_DLL_SYMBOLS=ON',
    '-DOVERRIDE_GIT_DESCRIBE=${config['duckdb_version']}',
    '-DBUILD_EXTENSIONS=core_functions;parquet;json;icu',
    '-DSTATICALLY_LINK_EXTENSIONS=core_functions;parquet;json;icu',
  ];
  var strip = 'strip';
  if (ios) {
    options.addAll([
      '-DCMAKE_SYSTEM_NAME=iOS',
      '-DCMAKE_OSX_SYSROOT=${target.contains('simulator') ? 'iphonesimulator' : 'iphoneos'}',
      '-DCMAKE_OSX_ARCHITECTURES=${target.endsWith('x64') ? 'x86_64' : 'arm64'}',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
      '-DCMAKE_INSTALL_NAME_DIR=@rpath',
      '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
    ]);
  } else if (linux) {
    options.add('-DCMAKE_POSITION_INDEPENDENT_CODE=ON');
  } else {
    final ndk = env['ANDROID_NDK_HOME'] ?? env['ANDROID_NDK_ROOT'];
    if (ndk == null || ndk.isEmpty) {
      throw ArgumentError(
        'Set ANDROID_NDK_HOME to an installed Android NDK (r28 or newer).',
      );
    }
    final host = switch (os) {
      'linux' => 'linux-x86_64',
      'macos' => 'darwin-x86_64',
      'windows' => 'windows-x86_64',
      _ => throw UnsupportedError('Unsupported Android build host: $os'),
    };
    strip = p.join(
      ndk,
      'toolchains',
      'llvm',
      'prebuilt',
      host,
      'bin',
      os == 'windows' ? 'llvm-strip.exe' : 'llvm-strip',
    );
    options.addAll([
      '-DCMAKE_TOOLCHAIN_FILE=${p.join(ndk, 'build', 'cmake', 'android.toolchain.cmake')}',
      '-DANDROID_ABI=${target.endsWith('arm64') ? 'arm64-v8a' : 'x86_64'}',
      '-DANDROID_PLATFORM=android-21',
      '-DANDROID_STL=c++_static',
      '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384',
    ]);
  }
  final directory = output.absolute;
  await directory.create(recursive: true);
  final source = p.join(directory.path, 'source');
  final build = p.join(directory.path, 'build');
  if (!await Directory(source).exists()) {
    await run('git', [
      'clone',
      '--depth',
      '1',
      '--branch',
      config['duckdb_version'] as String,
      'https://github.com/duckdb/duckdb.git',
      source,
    ]);
  }
  final commit = (await run('git', ['-C', source, 'rev-parse', 'HEAD'])).trim();
  if (commit != config['duckdb_commit']) {
    throw StateError('Unexpected DuckDB source commit: $commit');
  }
  await run('cmake', ['-S', source, '-B', build, '-G', 'Ninja', ...options]);
  await run('cmake', [
    '--build',
    build,
    '--target',
    'duckdb',
    '--parallel',
    '$jobs',
  ]);
  final name = ios ? 'libduckdb.dylib' : 'libduckdb.so';
  final packaged = await File(
    p.join(build, 'src', name),
  ).copy(p.join(directory.path, name));
  if (ios) {
    await run('xcrun', ['strip', '-S', packaged.path]);
  } else {
    await run(strip, ['--strip-debug', packaged.path]);
  }
  return packaged;
}
