import 'dart:ffi';
import 'dart:io';

import 'package:dart_duckdb/src/api/open.dart';
import 'package:dart_duckdb/src/ffi/duckdb.g.dart';
import 'package:dart_duckdb/src/ffi/native_lookup.g.dart';
import 'package:meta/meta.dart';

/// Manages explicit library overrides. By default, build hooks provide DuckDB.
class OpenDynamicLibrary extends OpenLibrary {
  final Map<OperatingSystem, String> _overriddenPlatforms = {};

  OpenDynamicLibrary._();

  OperatingSystem? get os {
    if (Platform.isAndroid) return OperatingSystem.android;
    if (Platform.isIOS) return OperatingSystem.iOS;
    if (Platform.isLinux) return OperatingSystem.linux;
    if (Platform.isMacOS) return OperatingSystem.macOS;
    if (Platform.isWindows) return OperatingSystem.windows;
    return null;
  }

  /// Use an explicit override when supplied; otherwise resolve the hook asset.
  Bindings openBindings() {
    final path = _overriddenPlatforms[os];
    return path == null
        ? NativeAssetBindings()
        : Bindings(DynamicLibrary.open(path));
  }

  /// Override the native library before first accessing `duckdb`.
  ///
  /// To avoid the default build-time download as well, configure the build
  /// hook's `library_path` or `native_build: system` option.
  @override
  void overrideFor(OperatingSystem os, String path) {
    _overriddenPlatforms[os] = path;
  }

  @visibleForTesting
  @override
  void reset() => _overriddenPlatforms.clear();
}

final OpenLibrary open = OpenDynamicLibrary._();
