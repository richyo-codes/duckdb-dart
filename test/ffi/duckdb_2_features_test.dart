@TestOn('vm')
library;

import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:test/test.dart';

// Exercise 2.0 SQL through the public Dart API, including conversion and errors.
// VARIANT results are explicitly cast: direct VARIANT decoding is not supported.
void main() {
  late Database database;
  late Connection connection;

  setUp(() async {
    database = await duckdb.open(':memory:');
    connection = await duckdb.connect(database);
  });
  tearDown(() async {
    await connection.dispose();
    await database.dispose();
  });

  Future<List<List<Object?>>> rows(String sql) async {
    final result = await connection.query(sql);
    try {
      return result.fetchAll();
    } finally {
      await result.dispose();
    }
  }

  Future<void> createAudit() async {
    await connection.execute('''
      CREATE TABLE target (id INTEGER, val INTEGER);
      CREATE TABLE audit (id INTEGER, old_val INTEGER, new_val INTEGER);
      CREATE TRIGGER record_changes AFTER UPDATE ON target
      REFERENCING OLD TABLE AS o NEW TABLE AS n FOR EACH STATEMENT
      INSERT INTO audit SELECT n.id, o.val, n.val FROM o JOIN n USING (id);
      INSERT INTO target VALUES (1, 10), (2, 20), (3, NULL);
    ''');
  }

  group('DuckDB 2.0 triggers', () {
    test('statement trigger preserves old/new values and nulls', () async {
      await createAudit();
      await connection.execute('UPDATE target SET val = coalesce(val, 0) + 1');
      expect(await rows('SELECT * FROM audit ORDER BY id'), [
        [1, 10, 11],
        [2, 20, 21],
        [3, null, 1],
      ]);
      await connection.execute('UPDATE target SET val = 0 WHERE id = 99');
      expect(await rows('SELECT count(*) FROM audit'), [
        [3],
      ]);
    });

    test('rollback undoes both table and trigger writes', () async {
      await createAudit();
      await connection.execute('BEGIN TRANSACTION');
      await connection.execute('UPDATE target SET val = 99');
      expect(await rows('SELECT count(*) FROM audit'), [
        [3],
      ]);
      await connection.execute('ROLLBACK');
      expect(await rows('SELECT * FROM target ORDER BY id'), [
        [1, 10],
        [2, 20],
        [3, null],
      ]);
      expect(await rows('SELECT count(*) FROM audit'), [
        [0],
      ]);
    });

    test(
      'row trigger runs for prepared inserts and stops after drop',
      () async {
        await connection.execute('''
        CREATE TABLE target (id INTEGER);
        CREATE TABLE audit (id INTEGER);
        CREATE TRIGGER record_insert AFTER INSERT ON target FOR EACH ROW
        INSERT INTO audit VALUES (NEW.id);
      ''');
        final statement = await connection.prepare(
          'INSERT INTO target VALUES (?)',
        );
        try {
          for (final value in [7, null, 9]) {
            statement.bind(value, 1);
            final result = await statement.execute();
            await result.dispose();
          }
        } finally {
          await statement.dispose();
        }
        expect(await rows('SELECT id FROM audit ORDER BY id NULLS LAST'), [
          [7],
          [9],
          [null],
        ]);
        await connection.execute('DROP TRIGGER record_insert ON target');
        await connection.execute('INSERT INTO target VALUES (11)');
        expect(await rows('SELECT count(*) FROM audit'), [
          [3],
        ]);
        expect(await rows('SELECT count(*) FROM target'), [
          [4],
        ]);
      },
    );
  });

  group('DuckDB 2.0 data-modifying CTEs', () {
    setUp(() async {
      await connection.execute('''
        CREATE TABLE staging (id INTEGER PRIMARY KEY, label VARCHAR);
        CREATE TABLE archive (id INTEGER PRIMARY KEY, label VARCHAR);
        INSERT INTO staging VALUES (1, 'one'), (2, NULL), (3, '雪');
      ''');
    });

    test(
      'DELETE RETURNING moves each row exactly once, including nulls',
      () async {
        const move = '''WITH moved AS MATERIALIZED (
        DELETE FROM staging WHERE id <= 2 RETURNING *
      ) INSERT INTO archive SELECT * FROM moved''';
        await connection.execute(move);
        await connection.execute(move);
        expect(await rows('SELECT * FROM archive ORDER BY id'), [
          [1, 'one'],
          [2, null],
        ]);
        expect(await rows('SELECT * FROM staging'), [
          [3, '雪'],
        ]);
      },
    );

    test(
      'prepared UPDATE CTE returns metadata and handles zero matches',
      () async {
        final statement = await connection.prepare('''
        WITH changed AS MATERIALIZED (
          UPDATE staging SET label = ? WHERE id = ? RETURNING id, label
        ) SELECT id, label FROM changed
      ''');
        try {
          statement.bindParams(['updated 雪', 3]);
          final result = await statement.execute();
          try {
            expect(result.columnNames, ['id', 'label']);
            expect(result.fetchAll(), [
              [3, 'updated 雪'],
            ]);
          } finally {
            await result.dispose();
          }
          statement.bindParams(['absent', 99]);
          final empty = await statement.execute();
          try {
            expect(empty.fetchAll(), isEmpty);
          } finally {
            await empty.dispose();
          }
        } finally {
          await statement.dispose();
        }
        expect(await rows('SELECT label FROM staging WHERE id = 3'), [
          ['updated 雪'],
        ]);
      },
    );

    test(
      'constraint failure rolls back the entire move and connection recovers',
      () async {
        await connection.execute("INSERT INTO archive VALUES (1, 'existing')");
        await expectLater(
          connection.execute('''
        WITH moved AS MATERIALIZED (DELETE FROM staging RETURNING *)
        INSERT INTO archive SELECT * FROM moved
      '''),
          throwsA(isA<DuckDBException>()),
        );
        expect(await rows('SELECT * FROM staging ORDER BY id'), [
          [1, 'one'],
          [2, null],
          [3, '雪'],
        ]);
        expect(await rows('SELECT * FROM archive'), [
          [1, 'existing'],
        ]);
      },
    );
  });

  group('DuckDB 2.0 VARIANT through explicit SQL conversions', () {
    test(
      'nested fields, missing keys and lists decode to supported Dart types',
      () async {
        expect(
          await rows('''
        WITH input AS (SELECT {'name': '雪', 'items': [1, 2, 3]}::VARIANT AS v)
        SELECT variant_extract_string(v, 'name'),
          variant_exists(v, 'items'), variant_exists(v, 'missing'),
          variant_extract_string(v, 'missing'),
          variant_array_length(variant_extract(v, 'items')),
          variant_extract(v, 'items')::INTEGER[] FROM input
      '''),
          [
            [
              '雪',
              true,
              false,
              null,
              BigInt.from(3),
              [1, 2, 3],
            ],
          ],
        );
      },
    );

    test(
      'prepared values can be stored as VARIANT and cast back without rounding',
      () async {
        await connection.execute('CREATE TABLE variants (value VARIANT)');
        final statement = await connection.prepare(
          'INSERT INTO variants VALUES (?::BIGINT::VARIANT)',
        );
        const values = [9007199254740993, -9007199254740993];
        try {
          for (final value in [...values, null]) {
            statement.bind(value, 1);
            final result = await statement.execute();
            await result.dispose();
          }
        } finally {
          await statement.dispose();
        }
        expect(
          await rows(
            'SELECT value::BIGINT FROM variants ORDER BY value::BIGINT NULLS LAST',
          ),
          [
            [values[1]],
            [values[0]],
            [null],
          ],
        );
      },
    );
  });

  test('nearest join returns deterministic top-k distances', () async {
    expect(
      await rows('''
      SELECT q.id, t.id FROM (VALUES (1, [0.0, 0.0]::FLOAT[2])) q(id, embedding)
      INNER JOIN (VALUES (10, [1.0, 0.0]::FLOAT[2]),
                         (20, [3.0, 0.0]::FLOAT[2]),
                         (30, [2.0, 0.0]::FLOAT[2])) t(id, embedding)
      NEAREST 2 BY DISTANCE array_distance(q.embedding, t.embedding)
      ORDER BY t.id
    '''),
      [
        [1, 10],
        [1, 30],
      ],
    );
  });
}
