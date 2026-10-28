import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/attendance_event.dart';
import 'attendance_local_data_source.dart';

class AttendanceSyncCoordinator {
  final AttendanceLocalDataSource _localDataSource;
  final ApiClient _apiClient;

  bool _isSyncing = false;

  AttendanceSyncCoordinator({required AttendanceLocalDataSource localDataSource, required ApiClient apiClient})
    : _localDataSource = localDataSource,
      _apiClient = apiClient;

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
          'occurredAt': event.occurredAt.toUtc().toIso8601String(),
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
