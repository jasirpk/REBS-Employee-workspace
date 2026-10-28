
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/attendance_event.dart';

class AttendanceLocalDataSource {
  final AppDatabase _appDatabase;

  AttendanceLocalDataSource(this._appDatabase);

  Future<int> saveEvent(AttendanceEvent event) async {
    final db = await _appDatabase.database;

    return db.insert(
      'attendance_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<AttendanceEvent>> getAllEvents() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'attendance_events',
      orderBy: 'local_id ASC',
    );

    return rows.map(AttendanceEvent.fromMap).toList();
  }

  Future<List<AttendanceEvent>> getPendingEvents() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'attendance_events',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'local_id ASC',
    );

    return rows.map(AttendanceEvent.fromMap).toList();
  }

  Future<List<AttendanceEvent>> getEventsForDate(
      String companyDate,
      ) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'attendance_events',
      where: 'company_date = ?',
      whereArgs: [companyDate],
      orderBy: 'local_id ASC',
    );

    return rows.map(AttendanceEvent.fromMap).toList();
  }

  Future<void> updateSyncStatus({
    required String eventId,
    required AttendanceSyncStatus status,
    String? rejectReason,
  }) async {
    final db = await _appDatabase.database;

    final updated = await db.update(
      'attendance_events',
      {
        'status': switch (status) {
          AttendanceSyncStatus.pending => 'PENDING',
          AttendanceSyncStatus.synced => 'SYNCED',
          AttendanceSyncStatus.rejected => 'REJECTED',
        },
        'reject_reason': rejectReason,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );

    if (updated == 0) {
      throw StateError('Attendance event not found: $eventId');
    }
  }

  Future<void> recordSyncAttempt(String eventId) async {
    final db = await _appDatabase.database;

    final updated = await db.rawUpdate(
      '''
      UPDATE attendance_events
      SET attempt_count = attempt_count + 1,
          last_attempt_at = ?
      WHERE event_id = ?
      ''',
      [DateTime.now().toUtc().toIso8601String(), eventId],
    );

    if (updated == 0) {
      throw StateError('Attendance event not found: $eventId');
    }
  }
}
