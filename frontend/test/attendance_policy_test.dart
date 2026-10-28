
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';
import 'package:frontend/features/attendance/domain/attendance_policy.dart';

void main() {
  const policy = AttendancePolicy();

  AttendanceEvent event(
      AttendanceEventType type, {
        AttendanceSyncStatus status = AttendanceSyncStatus.pending,
        int? localId,
      }) {
    return AttendanceEvent(
      localId: localId,
      eventId: 'event-${type.name}-${localId ?? 0}',
      employeeId: 'EMP001',
      type: type,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
      status: status,
    );
  }

  test('rejects checkout without check-in', () {
    final result = policy.validateAction(
      requestedType: AttendanceEventType.checkOut,
      todayEvents: [],
    );

    expect(result, 'You must check in before checking out.');
  });

  test('rejects a second check-in', () {
    final result = policy.validateAction(
      requestedType: AttendanceEventType.checkIn,
      todayEvents: [event(AttendanceEventType.checkIn)],
    );

    expect(result, 'You have already checked in today.');
  });

  test('allows checkout after check-in', () {
    final result = policy.validateAction(
      requestedType: AttendanceEventType.checkOut,
      todayEvents: [event(AttendanceEventType.checkIn)],
    );

    expect(result, isNull);
  });

  test('allows retry after rejected check-in', () {
    final result = policy.validateAction(
      requestedType: AttendanceEventType.checkIn,
      todayEvents: [
        event(
          AttendanceEventType.checkIn,
          status: AttendanceSyncStatus.rejected,
        ),
      ],
    );

    expect(result, isNull);
  });

  test('rejects a second checkout', () {
    final result = policy.validateAction(
      requestedType: AttendanceEventType.checkOut,
      todayEvents: [
        event(AttendanceEventType.checkIn, localId: 1),
        event(AttendanceEventType.checkOut, localId: 2),
      ],
    );

    expect(result, 'You have already checked out today.');
  });
}
