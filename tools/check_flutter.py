#!/usr/bin/env python3
"""Verify native asset loading from a fresh Flutter application."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix='duckdb-flutter-smoke-') as temporary:
    app = Path(temporary)
    subprocess.run(['flutter', 'create', '--empty', '--platforms=linux',
                    '--project-name=duckdb_native_smoke', '--no-pub', str(app)], check=True)
    pubspec = app / 'pubspec.yaml'
    pubspec.write_text(pubspec.read_text().replace(
        'dependencies:\n', f'dependencies:\n  dart_duckdb:\n    path: {ROOT.as_posix()}\n', 1))
    tests = app / 'test'
    tests.mkdir(exist_ok=True)
    (tests / 'native_test.dart').write_text('''
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter resolves the bundled native asset', () async {
    final database = await duckdb.open(':memory:');
    final connection = await duckdb.connect(database);
    final result = await connection.query('SELECT 42');
    try {
      expect(result.fetchAll(), [[42]]);
    } finally {
      await result.dispose();
      await connection.dispose();
      await database.dispose();
    }
  });
}
''')
    subprocess.run(['flutter', 'pub', 'get'], cwd=app, check=True)
    subprocess.run(['flutter', 'test', 'test/native_test.dart'], cwd=app, check=True)
