@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:test/test.dart';

void main() {
  test('native library and SQL report the expected runtime version', () async {
    final expected = Platform.environment['DUCKDB_TEST_VERSION'];
    if (expected != null) {
      // Catch accidentally loading an older bundled or system library.
      expect(duckdb.version, expected);
    }

    final database = await duckdb.open(':memory:');
    final connection = await duckdb.connect(database);
    try {
      final result = await connection.query('SELECT version()');
      try {
        expect(result.fetchAll(), [
          [duckdb.version],
        ]);
      } finally {
        await result.dispose();
      }
    } finally {
      await connection.dispose();
      await database.dispose();
    }
  });
}
