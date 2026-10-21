import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';

String binaryTarget(
  OS os,
  Architecture arch, {
  bool simulator = false,
  Object linuxLibc = 'glibc',
}) {
  if (arch != Architecture.x64 && arch != Architecture.arm64) {
    throw UnsupportedError(
      'No DuckDB binary for $os/$arch. Supported architectures are x64 and arm64.',
    );
  }
  if (os == OS.iOS) {
    if (!simulator && arch != Architecture.arm64) {
      throw UnsupportedError('iOS devices require arm64.');
    }
    return 'ios-${simulator ? 'simulator-' : ''}${arch.name}';
  }
  if (os == OS.linux) {
    if (linuxLibc != 'glibc' && linuxLibc != 'musl') {
      throw ArgumentError.value(linuxLibc, 'linux_libc', 'Use glibc or musl.');
    }
    return 'linux-${arch.name}${linuxLibc == 'musl' ? '-musl' : ''}';
  }
  if (os == OS.android || os == OS.macOS || os == OS.windows) {
    return '${os.name}-${arch.name}';
  }
  throw UnsupportedError('No DuckDB binary for $os.');
}

Future<List<int>> download(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  client.findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(minutes: 2));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'HTTP ${response.statusCode}. The native release may not be published yet. '
        'Use native_build: source or library_path to supply a local build.',
        uri: uri,
      );
    }
    return await response
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk))
        .timeout(const Duration(minutes: 5));
  } finally {
    client.close(force: true);
  }
}

Future<File> obtainBinary({
  required Map<String, dynamic> config,
  required String target,
  required String libraryName,
  required Directory cache,
  String? repository,
}) async {
  final desktop =
      (config['desktop'] as Map<String, dynamic>)[target]
          as Map<String, dynamic>?;
  late Uri url;
  late String expected;
  if (desktop != null) {
    url = Uri.parse(desktop['url'] as String);
    expected = desktop['sha256'] as String;
  } else {
    final repo = repository ?? config['repository'] as String;
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      throw ArgumentError.value(
        repo,
        'binary_repository',
        'Expected owner/repository.',
      );
    }
    final filename = 'duckdb-${config['duckdb_version']}-$target.tar.gz';
    url = Uri.parse(
      'https://github.com/$repo/releases/download/${config['release_tag']}/$filename',
    );
    // Release assets are immutable. The publisher uploads this digest alongside
    // each archive; desktop digests are pinned directly in native_config.json.
    final checksum = String.fromCharCodes(
      await download(Uri.parse('$url.sha256')),
    );
    expected = checksum.trim().split(RegExp(r'\s+')).first;
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    throw const FormatException('Invalid SHA-256 in native binary manifest.');
  }
  final entry = Directory('${cache.path}/$target-$expected');
  await entry.create(recursive: true);
  final archive = File('${entry.path}/archive.tar.gz');
  List<int> bytes;
  if (await archive.exists()) {
    bytes = await archive.readAsBytes();
    if (sha256.convert(bytes).toString() != expected) {
      bytes = await download(url);
    }
  } else {
    bytes = await download(url);
  }
  verifyDigest(bytes, expected);
  // Extract only the expected file, never arbitrary paths from an archive.
  final contents = extractLibrary(bytes, libraryName);
  final result = File('${entry.path}/$libraryName');
  await result.writeAsBytes(contents, flush: true);
  await archive.writeAsBytes(bytes, flush: true);
  return result;
}

void verifyDigest(List<int> bytes, String expected) {
  if (sha256.convert(bytes).toString() != expected) {
    throw const FormatException(
      'DuckDB archive SHA-256 mismatch. Refusing to bundle it.',
    );
  }
}

List<int> extractLibrary(List<int> bytes, String libraryName) {
  final archive = TarDecoder().decodeBytes(
    const GZipDecoder().decodeBytes(bytes),
  );
  final files = archive.files.where(
    (file) => file.name == libraryName && file.isFile && !file.isSymbolicLink,
  );
  if (files.length != 1) {
    throw FormatException(
      'Expected exactly one $libraryName in DuckDB archive.',
    );
  }
  return files.single.content;
}
