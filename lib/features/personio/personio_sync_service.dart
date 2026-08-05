import 'package:drift/drift.dart' show Value;

import '../../data/drift/database.dart';
import '../../data/drift/tables/personio_attendances_table.dart';
import '../../data/sync/synced_writes.dart';
import 'personio_client.dart';

/// Outcome of one [PersonioSyncService.pushRange] run, for display in the UI.
class PersonioSyncResult {
  const PersonioSyncResult({
    required this.created,
    required this.updated,
    required this.deleted,
    required this.failed,
  });

  final int created;
  final int updated;
  final int deleted;
  final int failed;

  int get total => created + updated + deleted + failed;
}

enum _Outcome { created, updated, deleted, skipped, failed }

/// Pushes finished time entries to Personio as WORK attendance periods.
/// Unlike JiraSyncService, every finished entry in the caller-selected date
/// range is a candidate (no per-entry opt-in field), and pending deletes are
/// always reconciled regardless of the selected range -- see
/// docs/superpowers/specs/2026-08-05-personio-sync-design.md.
class PersonioSyncService {
  PersonioSyncService({required this.db, required this.client, required this.writes});

  final AppDatabase db;
  final PersonioClient client;
  final SyncedWrites writes;

  Future<PersonioSyncResult> pushRange({required DateTime from, required DateTime to}) async {
    final attendancesByEntryId = {
      for (final a in await db.personioAttendancesDao.getAll()) a.id: a,
    };
    final counts = <_Outcome, int>{};

    for (final attendance in attendancesByEntryId.values) {
      if (attendance.status != PersonioAttendanceStatus.pendingDelete) continue;
      final outcome = await _reconcilePendingDelete(attendance);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    final entries = await db.timeEntriesDao.getAllEntries();
    for (final entry in entries) {
      if (entry.endAt == null) continue;
      if (!_isInRange(entry.startAt, from: from, to: to)) continue;
      final attendance = attendancesByEntryId[entry.id];
      if (attendance?.status == PersonioAttendanceStatus.pendingDelete) continue;
      final outcome = await _reconcileEntry(entry, attendance);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    return PersonioSyncResult(
      created: counts[_Outcome.created] ?? 0,
      updated: counts[_Outcome.updated] ?? 0,
      deleted: counts[_Outcome.deleted] ?? 0,
      failed: counts[_Outcome.failed] ?? 0,
    );
  }

  /// [from]/[to] are inclusive local calendar days; [entryStart] is compared
  /// by its local calendar date only, ignoring time-of-day.
  bool _isInRange(DateTime entryStart, {required DateTime from, required DateTime to}) {
    final local = entryStart.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return !date.isBefore(fromDate) && !date.isAfter(toDate);
  }

  String _safeErrorMessage(Object error) =>
      error is PersonioApiException ? error.message : 'Network or connection error';

  Future<_Outcome> _reconcilePendingDelete(PersonioAttendanceRow attendance) async {
    try {
      if (attendance.personioAttendanceId != null) {
        await client.deleteAttendance(periodId: attendance.personioAttendanceId!);
      }
      await writes.deletePersonioAttendanceState(attendance.id);
      return _Outcome.deleted;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(lastError: Value(_safeErrorMessage(e))),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _reconcileEntry(TimeEntry entry, PersonioAttendanceRow? attendance) async {
    if (attendance == null) {
      return _pushCreate(entry);
    }
    final needsUpdate = attendance.syncedAt == null || entry.updatedAt.isAfter(attendance.syncedAt!);
    if (!needsUpdate) return _Outcome.skipped;
    if (attendance.personioAttendanceId == null) {
      return _pushCreate(entry);
    }
    return _pushUpdate(entry, attendance);
  }

  Future<_Outcome> _pushCreate(TimeEntry entry) async {
    try {
      final periodId = await client.createAttendance(
        start: entry.startAt,
        end: entry.endAt!,
        comment: entry.description,
      );
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: periodId,
          status: PersonioAttendanceStatus.synced,
          lastError: null,
          syncedAt: DateTime.now().toUtc(),
        ),
      );
      return _Outcome.created;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: null,
          status: PersonioAttendanceStatus.error,
          lastError: _safeErrorMessage(e),
          syncedAt: null,
        ),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _pushUpdate(TimeEntry entry, PersonioAttendanceRow attendance) async {
    try {
      await client.updateAttendance(
        periodId: attendance.personioAttendanceId!,
        start: entry.startAt,
        end: entry.endAt!,
        comment: entry.description,
      );
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(
          status: PersonioAttendanceStatus.synced,
          syncedAt: Value(DateTime.now().toUtc()),
          lastError: const Value(null),
        ),
      );
      return _Outcome.updated;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(
          status: PersonioAttendanceStatus.error,
          lastError: Value(_safeErrorMessage(e)),
        ),
      );
      return _Outcome.failed;
    }
  }
}
