
import 'attendance_event.dart';

class AttendancePolicy {
  const AttendancePolicy();

  String? validateAction({
    required AttendanceEventType requestedType,
    required List<AttendanceEvent> todayEvents,
  }) {
    final activeEvents = todayEvents
        .where((event) => event.status != AttendanceSyncStatus.rejected)
        .toList()
      ..sort((a, b) => a.localId == null || b.localId == null
          ? a.occurredAt.compareTo(b.occurredAt)
          : a.localId!.compareTo(b.localId!));

    final hasCheckIn = activeEvents.any(
          (event) => event.type == AttendanceEventType.checkIn,
    );

    final hasCheckOut = activeEvents.any(
          (event) => event.type == AttendanceEventType.checkOut,
    );

    if (requestedType == AttendanceEventType.checkIn && hasCheckIn) {
      return 'You have already checked in today.';
    }

    if (requestedType == AttendanceEventType.checkOut && !hasCheckIn) {
      return 'You must check in before checking out.';
    }

    if (requestedType == AttendanceEventType.checkOut && hasCheckOut) {
      return 'You have already checked out today.';
    }

    return null;
  }
}
