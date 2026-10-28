import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/attendance_event.dart';
import 'attendance_local_data_source.dart';

class AttendanceSyncCoordinator {
  final AttendanceLocalDataSource _localDataSource;
  final ApiClient _apiClient;

  bool _isSyncing = false;

  // In-flight pulls by company date, so overlapping calls share one GET.
  final Map<String, Future<void>> _pullsInFlight = {};

  static final RegExp _companyDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  AttendanceSyncCoordinator({required AttendanceLocalDataSource localDataSource, required ApiClient apiClient})
    : _localDataSource = localDataSource,
      _apiClient = apiClient;

  // Imports the server's accepted events for [companyDate] into SQLite.
  // Network and HTTP errors propagate so callers can keep local data;
  // malformed responses throw a FormatException before anything is imported.
  Future<void> pullEventsForDate(String companyDate) {
    // Block body: remove() returns this same future, and whenComplete would
    // wait on it if it were returned from the callback.
    return _pullsInFlight[companyDate] ??= _pullEventsForDate(companyDate).whenComplete(() {
      _pullsInFlight.remove(companyDate);
    });
  }

  Future<void> _pullEventsForDate(String companyDate) async {
    if (!_companyDatePattern.hasMatch(companyDate)) {
      throw ArgumentError.value(companyDate, 'companyDate', 'must use YYYY-MM-DD format');
    }

    final month = companyDate.substring(0, 7);

    final response = await _apiClient.dio.get<Object?>('attendance', queryParameters: {'month': month});

    final data = response.data;

    if (data is! Map || data['month'] != month || data['records'] is! List) {
      throw const FormatException('Attendance history response is malformed.');
    }

    // Validate every record before filtering so a malformed response fails
    // visibly instead of importing a partial result.
    final serverEvents = (data['records'] as List).map(_eventFromServerRecord).toList();

    await _localDataSource.importSyncedEvents(serverEvents.where((event) => event.companyDate == companyDate).toList());
  }

  AttendanceEvent _eventFromServerRecord(Object? record) {
    if (record is! Map) {
      throw const FormatException('Attendance record must be an object.');
    }

    String requireString(String field) {
      final value = record[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Attendance record has an invalid "$field".');
      }
      return value;
    }

    double requireCoordinate(String field, double limit) {
      final value = record[field];
      if (value is! num || !value.isFinite || value.abs() > limit) {
        throw FormatException('Attendance record has an invalid "$field".');
      }
      return value.toDouble();
    }

    final type = switch (record['type']) {
      'CHECK_IN' => AttendanceEventType.checkIn,
      'CHECK_OUT' => AttendanceEventType.checkOut,
      _ => throw const FormatException('Attendance record has an invalid "type".'),
    };

    // Only accepted events may be imported as synced.
    if (record['status'] != 'SYNCED') {
      throw const FormatException('Attendance record has an invalid "status".');
    }

    // Require an explicit UTC offset so the instant is unambiguous.
    final occurredAt = DateTime.tryParse(requireString('occurredAt'));
    if (occurredAt == null || !occurredAt.isUtc) {
      throw const FormatException('Attendance record has an invalid "occurredAt".');
    }

    final companyDate = requireString('companyDate');
    if (!_companyDatePattern.hasMatch(companyDate)) {
      throw const FormatException('Attendance record has an invalid "companyDate".');
    }

    return AttendanceEvent(
      eventId: requireString('eventId'),
      employeeId: requireString('employeeId'),
      type: type,
      occurredAt: occurredAt,
      companyDate: companyDate,
      latitude: requireCoordinate('latitude', 90),
      longitude: requireCoordinate('longitude', 180),
      // The server does not return accuracy. Imported events are already
      // synced, so this placeholder is never sent or used for validation.
      accuracyMeters: 0,
      status: AttendanceSyncStatus.synced,
    );
  }

  // the helper method will process the queue in order.
  Future<void> syncPendingEvents() async {
    if (_isSyncing) return;

    _isSyncing = true;

    try {
      final pendingEvents = await _localDataSource.getPendingEvents();

      for (final event in pendingEvents) {
        // Reload the current state because an earlier event may have
        // changed this event's status (for example, rejected its checkout).
        final currentEvents = await _localDataSource.getEventsForDate(
          event.companyDate,
        );

        final currentEvent = currentEvents
            .where((item) => item.eventId == event.eventId)
            .firstOrNull;

        if (currentEvent == null ||
            currentEvent.status != AttendanceSyncStatus.pending) {
          continue;
        }

        await _syncSingleEvent(currentEvent);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSingleEvent(AttendanceEvent event) async {
    await _localDataSource.recordSyncAttempt(event.eventId);

    try {
      await _apiClient.dio.post(
        'attendance/events',
        data: {
          'eventId': event.eventId,
          'type': event.typeValue,
          // Milliseconds only: the server stores toISOString() and compares a
          // retried eventId's payload against it, so microseconds would turn a
          // safe retry into an IDEMPOTENCY_KEY_REUSED rejection.
          'occurredAt': DateTime.fromMillisecondsSinceEpoch(event.occurredAt.millisecondsSinceEpoch, isUtc: true).toIso8601String(),
          'companyDate': event.companyDate,
          'latitude': event.latitude,
          'longitude': event.longitude,
          'accuracyMeters': event.accuracyMeters,
        },
      );

      await _localDataSource.updateSyncStatus(eventId: event.eventId, status: AttendanceSyncStatus.synced);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;

      if (statusCode == 409 || statusCode == 422) {
        final responseData = error.response?.data;

        final reason = responseData is Map ? (responseData['message'] ?? responseData['error'] ?? responseData['code'])?.toString() : null;

        await _localDataSource.updateSyncStatus(
          eventId: event.eventId,
          status: AttendanceSyncStatus.rejected,
          rejectReason: reason ?? 'Attendance event rejected by server.',
        );
        if (event.type == AttendanceEventType.checkIn) {
          await _rejectDependentCheckout(event);
        }
        return;
      }

      // Network errors, timeouts, and server errors may be temporary.
      // Stop here and leave this event PENDING for a safe retry.
      rethrow;
    }
  }

  Future<void> _rejectDependentCheckout(AttendanceEvent rejectedCheckIn) async {
    final events = await _localDataSource.getEventsForDate(rejectedCheckIn.companyDate);

    for (final event in events) {
      if (event.employeeId != rejectedCheckIn.employeeId) continue;
      if (event.type != AttendanceEventType.checkOut) continue;
      if (event.status != AttendanceSyncStatus.pending) continue;

      await _localDataSource.updateSyncStatus(
        eventId: event.eventId,
        status: AttendanceSyncStatus.rejected,
        rejectReason: 'Checkout rejected because its check-in was rejected.',
      );
    }
  }
}
