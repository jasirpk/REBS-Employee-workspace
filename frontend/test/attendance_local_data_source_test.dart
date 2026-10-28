
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/features/attendance/data/attendance_local_data_source.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';

import 'test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late AttendanceLocalDataSource localDataSource;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDatabase = await createTestDatabase();
    localDataSource = AttendanceLocalDataSource(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  AttendanceEvent buildEvent(
    String eventId, {
    AttendanceEventType type = AttendanceEventType.checkIn,
    AttendanceSyncStatus status = AttendanceSyncStatus.pending,
    String? rejectReason,
  }) {
    return AttendanceEvent(
      eventId: eventId,
      employeeId: 'EMP001',
      type: type,
      occurredAt: DateTime.utc(2026, 10, 28, 4),
      companyDate: '2026-10-28',
      latitude: 11.190723,
      longitude: 75.950761,
      accuracyMeters: 0,
      status: status,
      rejectReason: rejectReason,
    );
  }

  test('Attendance event model preserves event data', () {
    final original = AttendanceEvent(
      eventId: 'test-event-001',
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
    );
    final restored = AttendanceEvent.fromMap({
      ...original.toMap(),
      'local_id': 1,
    });

    expect(restored.eventId, original.eventId);
    expect(restored.employeeId, original.employeeId);
    expect(restored.type, AttendanceEventType.checkIn);
    expect(restored.status, AttendanceSyncStatus.pending);
    expect(restored.companyDate, '2026-10-28');
  });

  group('importSyncedEvents', () {
    test('inserts a new server event as synced', () async {
      // The caller's status is ignored; imported events are always synced.
      await localDataSource.importSyncedEvents([buildEvent('server-001')]);

      final events = await localDataSource.getAllEvents();

      expect(events, hasLength(1));
      expect(events.first.eventId, 'server-001');
      expect(events.first.type, AttendanceEventType.checkIn);
      expect(events.first.status, AttendanceSyncStatus.synced);
      expect(events.first.rejectReason, isNull);
      expect(events.first.occurredAt, DateTime.utc(2026, 10, 28, 4));
    });

    test('repeated import does not duplicate events', () async {
      final serverEvents = [
        buildEvent('server-001'),
        buildEvent('server-002', type: AttendanceEventType.checkOut),
      ];

      await localDataSource.importSyncedEvents(serverEvents);
      await localDataSource.importSyncedEvents(serverEvents);

      final events = await localDataSource.getAllEvents();

      expect(events.map((event) => event.eventId), ['server-001', 'server-002']);
      expect(events.every((event) => event.status == AttendanceSyncStatus.synced), isTrue);
    });

    test('promotes a pending event with the same eventId to synced', () async {
      final localId = await localDataSource.saveEvent(buildEvent('shared-001'));
      await localDataSource.recordSyncAttempt('shared-001');

      await localDataSource.importSyncedEvents([buildEvent('shared-001')]);

      final events = await localDataSource.getAllEvents();

      expect(events, hasLength(1));
      expect(events.first.localId, localId);
      expect(events.first.status, AttendanceSyncStatus.synced);
      expect(events.first.rejectReason, isNull);
      expect(events.first.attemptCount, 1);
    });

    test('leaves a rejected event with the same eventId unchanged', () async {
      await localDataSource.saveEvent(
        buildEvent('shared-002', status: AttendanceSyncStatus.rejected, rejectReason: 'Outside office geofence'),
      );

      await localDataSource.importSyncedEvents([buildEvent('shared-002')]);

      final events = await localDataSource.getAllEvents();

      expect(events, hasLength(1));
      expect(events.first.status, AttendanceSyncStatus.rejected);
      expect(events.first.rejectReason, 'Outside office geofence');
    });

    test('imports a server check-in alongside a rejected local check-in', () async {
      await localDataSource.saveEvent(
        buildEvent(
          'local-rejected-001',
          status: AttendanceSyncStatus.rejected,
          rejectReason: 'A check-in already exists for this day',
        ),
      );

      await localDataSource.importSyncedEvents([buildEvent('android-001')]);

      final events = await localDataSource.getEventsForDate('2026-10-28');

      expect(events, hasLength(2));
      expect(events[0].eventId, 'local-rejected-001');
      expect(events[0].status, AttendanceSyncStatus.rejected);
      expect(events[1].eventId, 'android-001');
      expect(events[1].status, AttendanceSyncStatus.synced);
    });

    test('skips a server check-in that conflicts with a different pending local check-in', () async {
      await localDataSource.saveEvent(buildEvent('local-pending-001'));

      await localDataSource.importSyncedEvents([
        buildEvent('android-001'),
        buildEvent('android-002', type: AttendanceEventType.checkOut),
      ]);

      final events = await localDataSource.getAllEvents();

      // The pending check-in is untouched and the conflicting check-in is
      // skipped, while the rest of the import still succeeds.
      expect(events.map((event) => event.eventId), ['local-pending-001', 'android-002']);
      expect(events[0].status, AttendanceSyncStatus.pending);
      expect(events[1].status, AttendanceSyncStatus.synced);
    });
  });
}
