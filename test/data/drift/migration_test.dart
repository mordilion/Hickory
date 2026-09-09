import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:sqlite3/sqlite3.dart';

// The upgrade path itself, which no other test covers: a released version
// jumps several schema versions at once, and the steps then run in one
// pass rather than one per development session. That difference is what
// hid the 1.3.2 -> 1.4.0 failure -- a developer's database was already at
// 11 when 12 was written, so `from < 11` never ran beside `from < 12`.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hickory_migration_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// A database file as [version] left it. Only `app_settings` is written
  /// out: it is the single pre-existing table any step above 8 touches, so
  /// the rest would be scenery.
  File seed(int version, {bool withAppSettings = false}) {
    final file = File('${dir.path}/hickory.sqlite');
    final raw = sqlite3.open(file.path);
    if (withAppSettings) {
      raw.execute('''
        CREATE TABLE app_settings (
          id TEXT NOT NULL,
          date_format TEXT NOT NULL DEFAULT 'iso',
          time_format TEXT NOT NULL DEFAULT '24h',
          quick_add_durations_minutes TEXT NOT NULL DEFAULT '15,30,60',
          count_paused_time_as_break INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        )
      ''');
    }
    raw.execute('PRAGMA user_version = $version');
    raw.close();
    return file;
  }

  Future<int> schemaVersionOf(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.data.values.first as int;
  }

  test('a 1.3.2 database (schema 8) upgrades all the way to the current schema', () async {
    final db = AppDatabase.forTesting(NativeDatabase(seed(8, withAppSettings: true)));
    addTearDown(db.close);

    // Any query opens the database, which is when the migration runs.
    expect(await db.absencesDao.watchAllAbsences().first, isEmpty);
    expect(await schemaVersionOf(db), 13);
  });

  test('a database that predates the absences table does not add its column twice', () async {
    // Schema 10 has the types table but not `absences`, so step 11 creates
    // it -- already carrying half_day_part -- and step 12 must not try to
    // add that column on top.
    final db = AppDatabase.forTesting(NativeDatabase(seed(10)));
    addTearDown(db.close);

    expect(await db.absencesDao.watchAllAbsences().first, isEmpty);
    expect(await schemaVersionOf(db), 13);
  });

  test('a database that already has the absences table still gains the column', () async {
    final file = seed(11);
    final raw = sqlite3.open(file.path);
    // The schema-11 shape: the table as it was before half_day_part.
    raw.execute('''
      CREATE TABLE absences (
        id TEXT NOT NULL,
        date INTEGER NOT NULL,
        absence_type_id TEXT NOT NULL,
        portion TEXT NOT NULL,
        start_at INTEGER NULL,
        end_at INTEGER NULL,
        note TEXT NULL,
        device_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
    raw.execute(
      "INSERT INTO absences VALUES ('a1', 0, 't1', 'fullDay', NULL, NULL, NULL, 'd', 0, 0)",
    );
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final absences = await db.absencesDao.watchAllAbsences().first;
    expect(absences.single.halfDayPart, isNull, reason: 'an existing row keeps its data');
    expect(await schemaVersionOf(db), 13);
  });

  /// The DDL the current schema produces, read back from SQLite so a
  /// half-migrated file can be built without hand-copying definitions that
  /// would drift away from the tables themselves.
  Future<Map<String, String>> currentDdl() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final rows = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL",
        )
        .get();
    final ddl = {
      for (final row in rows) row.read<String>('name'): row.read<String>('sql'),
    };
    await db.close();
    return ddl;
  }

  test('a database left half-migrated by the broken 1.4.0 recovers', () async {
    // What 1.4.0 leaves on disk: it got as far as creating the absence
    // tables and adding the target columns, then threw on half_day_part.
    // SQLite kept all of that and user_version stayed at 8, so the fixed
    // build runs the very same steps again over work already done.
    final ddl = await currentDdl();
    final file = File('${dir.path}/hickory.sqlite');
    final raw = sqlite3.open(file.path);
    for (final table in ['app_settings', 'absence_types', 'absences']) {
      raw.execute(ddl[table]!);
    }
    raw.execute('PRAGMA user_version = 8');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.absencesDao.watchAllAbsences().first, isEmpty);
    expect(await schemaVersionOf(db), 13);
  });

  test('a database from before app_settings existed upgrades too', () async {
    // Schema 2: app_settings is created at step 3 in its current shape,
    // so steps 5, 7 and 9 must not add columns it already carries. Only
    // the tables the steps above 2 touch are seeded; the rest is scenery.
    final file = File('${dir.path}/hickory.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute('CREATE TABLE time_entries (id TEXT NOT NULL, PRIMARY KEY (id))');
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.absencesDao.watchAllAbsences().first, isEmpty);
    expect(await schemaVersionOf(db), 13);
  });

  test('a step that fails rolls the whole migration back', () async {
    // An index squatting on the name step 11 wants for its table: that
    // step fails after step 9 has added fourteen columns and step 10 has
    // created a table, so there is real work to undo.
    final file = File('${dir.path}/hickory.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute(
      'CREATE TABLE app_settings (id TEXT NOT NULL, '
      "date_format TEXT NOT NULL DEFAULT 'iso', "
      "time_format TEXT NOT NULL DEFAULT '24h', "
      "quick_add_durations_minutes TEXT NOT NULL DEFAULT '15,30,60', "
      'count_paused_time_as_break INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER NOT NULL, PRIMARY KEY (id))',
    );
    raw.execute('CREATE INDEX absences ON app_settings (id)');
    raw.execute('PRAGMA user_version = 8');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(db.absencesDao.watchAllAbsences().first, throwsA(anything));
    await db.close();

    final after = sqlite3.open(file.path);
    final version = after.select('PRAGMA user_version').first.values.first;
    final tables = after
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name'] as String)
        .toSet();
    final settingsColumns = after
        .select('PRAGMA table_info(app_settings)')
        .map((row) => row['name'] as String)
        .toSet();
    after.close();

    expect(version, 8, reason: 'a failed migration leaves the schema version alone');
    expect(
      tables,
      isNot(contains('absence_types')),
      reason: 'the table an earlier step created is rolled back with it',
    );
    expect(
      settingsColumns,
      isNot(contains('target_minutes_monday')),
      reason: 'and so are the columns it added',
    );
  });
}
