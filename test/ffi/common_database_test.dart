@TestOn('vm')
library;

import 'package:dart_duckdb/src/ffi/impl/utils.dart';
import 'package:dart_duckdb/src/ffi/load_library.dart';
import 'package:test/test.dart';

void main() {
  test('hook asset resolves DuckDB symbols', () {
    final bindings = (open as OpenDynamicLibrary).openBindings();
    expect(bindings.duckdb_library_version().readString(), startsWith('v'));
  });
}
