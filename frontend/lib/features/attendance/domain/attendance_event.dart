
enum AttendanceEventType {
  checkIn,
  checkOut,
}

enum AttendanceSyncStatus {
  pending,
  synced,
  rejected,
}

class AttendanceEvent {
  final int? localId;
  final String eventId;
  final String employeeId;
  final AttendanceEventType type;
  final DateTime occurredAt;
  final String companyDate;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final AttendanceSyncStatus status;
  final String? rejectReason;
  final int attemptCount;
  final DateTime? lastAttemptAt;

  const AttendanceEvent({
    this.localId,
    required this.eventId,
    required this.employeeId,
    required this.type,
    required this.occurredAt,
    required this.companyDate,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.status = AttendanceSyncStatus.pending,
    this.rejectReason,
    this.attemptCount = 0,
    this.lastAttemptAt,
  });

  String get typeValue =>
      type == AttendanceEventType.checkIn ? 'CHECK_IN' : 'CHECK_OUT';

  String get statusValue {
    switch (status) {
      case AttendanceSyncStatus.pending:
        return 'PENDING';
      case AttendanceSyncStatus.synced:
        return 'SYNCED';
      case AttendanceSyncStatus.rejected:
        return 'REJECTED';
    }
  }

  Map<String, Object?> toMap() {
    return {
      'event_id': eventId,
      'employee_id': employeeId,
      'type': typeValue,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'company_date': companyDate,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'status': statusValue,
      'reject_reason': rejectReason,
      'attempt_count': attemptCount,
      'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    };
  }

  factory AttendanceEvent.fromMap(Map<String, Object?> map) {
    final type = switch (map['type']) {
      'CHECK_IN' => AttendanceEventType.checkIn,
      'CHECK_OUT' => AttendanceEventType.checkOut,
      _ => throw FormatException('Unknown attendance type: ${map['type']}'),
    };

    final status = switch (map['status']) {
      'PENDING' => AttendanceSyncStatus.pending,
      'SYNCED' => AttendanceSyncStatus.synced,
      'REJECTED' => AttendanceSyncStatus.rejected,
      _ => throw FormatException(
        'Unknown attendance status: ${map['status']}',
      ),
    };

    return AttendanceEvent(
      localId: map['local_id'] as int?,
      eventId: map['event_id'] as String,
      employeeId: map['employee_id'] as String,
      type: type,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      companyDate: map['company_date'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num).toDouble(),
      status: status,
      rejectReason: map['reject_reason'] as String?,
      attemptCount: map['attempt_count'] as int,
      lastAttemptAt: map['last_attempt_at'] == null
          ? null
          : DateTime.parse(map['last_attempt_at'] as String),
    );
  }
}
