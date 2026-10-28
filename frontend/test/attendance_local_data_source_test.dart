
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/features/attendance/data/attendance_local_data_source.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';

void main() {
  late AppDatabase appDatabase;
  late AttendanceLocalDataSource dataSource;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDatabase = AppDatabase();
    dataSource = AttendanceLocalDataSource(appDatabase);

    // The production database wrapper uses the normal platform factory.
    // The test needs an in-memory database instead, so use the test
    // database implementation shown in the next step if necessary.
  });

  tearDown(() async {
    await appDatabase.close();
  });

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
}
