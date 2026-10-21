import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../hook/native_binary.dart';

void main() {
  test('auto prefers binary and builds only when release is missing', () async {
    var builds = 0;
    Future<File> source() async {
      builds++;
      return File('compiled');
    }

    final binary = await obtainBinaryOrBuild(
      binary: () async => File('downloaded'),
      source: source,
      allowSourceFallback: true,
    );
    expect(binary.path, 'downloaded');
    expect(builds, 0);
    final compiled = await obtainBinaryOrBuild(
      binary: () async => throw NativeBinaryUnavailable(
        Uri.parse('https://example.invalid/release'),
      ),
      source: source,
      allowSourceFallback: true,
    );
    expect(compiled.path, 'compiled');
    expect(builds, 1);
  });
  test(
    'strict binary and integrity or transport errors never compile',
    () async {
      var builds = 0;
      for (final error in [
        NativeBinaryUnavailable(Uri.parse('https://example.invalid/release')),
        const FormatException('bad checksum'),
        const HttpException('HTTP 503'),
        const SocketException('offline'),
      ]) {
        for (final auto in [false, true]) {
          if (auto && error is NativeBinaryUnavailable) continue;
          await expectLater(
            obtainBinaryOrBuild(
              binary: () async => throw error,
              source: () async {
                builds++;
                return File('compiled');
              },
              allowSourceFallback: auto,
            ),
            throwsA(same(error)),
          );
        }
      }
      expect(builds, 0);
    },
  );
  test(
    'HTTP 404 is classified as unavailable but server errors are not',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = int.parse(request.uri.path.substring(1));
        await request.response.close();
      });
      for (final status in [404, 403, 500]) {
        await expectLater(
          download(Uri.parse('http://127.0.0.1:${server.port}/$status')),
          throwsA(
            status == 404
                ? isA<NativeBinaryUnavailable>()
                : isA<HttpException>().having(
                    (e) => e is NativeBinaryUnavailable,
                    'missing release',
                    false,
                  ),
          ),
        );
      }
    },
  );
  test(
    'selects target architecture, libc and iOS SDK independently of host',
    () {
      expect(binaryTarget(OS.linux, Architecture.arm64), 'linux-arm64');
      expect(
        binaryTarget(OS.linux, Architecture.x64, linuxLibc: 'musl'),
        'linux-x64-musl',
      );
      expect(binaryTarget(OS.iOS, Architecture.arm64), 'ios-arm64');
      expect(
        binaryTarget(OS.iOS, Architecture.arm64, simulator: true),
        'ios-simulator-arm64',
      );
      expect(
        binaryTarget(OS.iOS, Architecture.x64, simulator: true),
        'ios-simulator-x64',
      );
      expect(binaryTarget(OS.android, Architecture.x64), 'android-x64');
      expect(binaryTarget(OS.macOS, Architecture.arm64), 'macos-arm64');
      expect(binaryTarget(OS.windows, Architecture.x64), 'windows-x64');
      expect(
        () => binaryTarget(OS.android, Architecture.arm),
        throwsUnsupportedError,
      );
      expect(
        () => binaryTarget(OS.iOS, Architecture.x64),
        throwsUnsupportedError,
      );
      expect(
        () => binaryTarget(OS.linux, Architecture.x64, linuxLibc: 'unknown'),
        throwsArgumentError,
      );
    },
  );

  test('rejects corrupted binaries before extraction', () {
    final bytes = [1, 2, 3];
    verifyDigest(bytes, sha256.convert(bytes).toString());
    expect(
      () => verifyDigest([1, 2, 4], sha256.convert(bytes).toString()),
      throwsFormatException,
    );
  });

  test('extracts only the expected library and rejects missing entries', () {
    final archive = Archive()
      ..addFile(ArchiveFile('libduckdb.so', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('../outside', 1, [4]));
    final bytes = const GZipEncoder().encode(TarEncoder().encode(archive));
    expect(extractLibrary(bytes, 'libduckdb.so'), [1, 2, 3]);
    expect(() => extractLibrary(bytes, 'duckdb.dll'), throwsFormatException);
  });
}
