import 'dart:io';

import 'package:dart_duckdb/dart_duckdb.dart';

Future<void> main() async {
  final database = await duckdb.open(':memory:');
  final connection = await duckdb.connect(database);
  try {
    final result = await connection.query('SELECT 42');
    try {
      if (result.fetchAll().single.single != 42) {
        throw StateError('DuckDB query returned an unexpected result.');
      }
      stdout.writeln('DuckDB ${duckdb.version}: SELECT 42 passed');
    } finally {
      await result.dispose();
    }
  } finally {
    await connection.dispose();
    await database.dispose();
  }
}
