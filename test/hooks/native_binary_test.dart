import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../hook/native_binary.dart';

void main() {
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
