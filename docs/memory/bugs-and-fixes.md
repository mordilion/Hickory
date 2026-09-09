# Bugs and Fixes

Root-cause notes for bugs that reached a release. One entry per bug, newest first.

## 1.4.0 bricked every upgrade from 1.3.x (endless spinner)

- **Symptom:** after updating 1.3.2 → 1.4.0 the app showed a spinner forever. No error
  reached the user: the database never opened, so every provider stayed pending.
- **Cause:** `onUpgrade` in `lib/data/drift/database.dart` ran
  `if (from < 11) createTable(absences)` and then
  `if (from < 12) addColumn(absences, halfDayPart)`. `Migrator.createTable` builds the
  table from its **current** definition, so the table already had `half_day_part` and the
  `ALTER TABLE` failed with `duplicate column name`.
- **Why no test caught it:** nothing exercised `onUpgrade` at all, and a developer's
  database is always *past* the create step when the column step is written — locally
  `from` was 11, so the two branches never ran together. Only a released version jumps
  8 → 13 in one pass.
- **Why it was worse than a crash:** the migration was not transactional. SQLite kept the
  tables and columns written before the error while `user_version` stayed at 8, so a
  merely corrected build would have failed again on the *next* step over work already
  done. Half-migrated files exist in the wild and have to heal themselves.
- **Fix (1.4.1):** all steps run inside one `BEGIN`/`COMMIT`/`ROLLBACK` via
  `customStatement`, and `_addColumnIfMissing` treats `duplicate column name` as done.
  `test/data/drift/migration_test.dart` seeds databases at schema 2, 8, 10, 11 and at the
  half-migrated 1.4.0 state, and asserts a failing step rolls everything back.
- **Rule that came out of it:** migrations are always transactional and always idempotent,
  and the upgrade path is tested from every released schema version. Written down in
  `.claude/rules/processes/dart-database-migrations.md`.
