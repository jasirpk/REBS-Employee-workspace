import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/time/company_clock.dart';
import '../data/attendance_local_data_source.dart';
import '../data/attendance_sync_coordinator.dart';
import '../domain/attendance_event.dart';
import '../domain/attendance_service.dart';
import '../domain/office_location.dart';
import 'attendance_state.dart';

class AttendanceCubit extends Cubit<AttendanceState> {
  final AttendanceLocalDataSource _localDataSource;
  final AttendanceService _attendanceService;
  final AttendanceSyncCoordinator _syncCoordinator;

  // Rejection reasons the backend sends with ATTENDANCE_ALREADY_EXISTS.
  // The sync coordinator stores the response message (or the code when no
  // message is present) as the reject reason, so match on those values.
  static const Set<String> _duplicateRejectReasons = {
    'ATTENDANCE_ALREADY_EXISTS',
    'A check-in already exists for this day',
    'A check-out already exists for this day',
    'Simulated duplicate attendance conflict',
  };

  Future<void>? _loadTodayInFlight;

  final Stream<List<ConnectivityResult>>? _connectivityChanges;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  // Null until the first connectivity event arrives.
  bool? _wasOnline;

  AttendanceCubit({
    required AttendanceLocalDataSource localDataSource,
    required AttendanceService attendanceService,
    required AttendanceSyncCoordinator syncCoordinator,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) : _localDataSource = localDataSource,
       _attendanceService = attendanceService,
       _syncCoordinator = syncCoordinator,
       _connectivityChanges = connectivityChanges,
       super(const AttendanceState());

  // Overlapping calls (e.g. a rebuild while startup is still loading)
  // share one load and therefore one history pull.
  Future<void> loadToday() {
    return _loadTodayInFlight ??= _loadToday().whenComplete(() {
      _loadTodayInFlight = null;
    });
  }

  Future<void> _loadToday() async {
    final companyDate = CompanyClock.today();

    emit(state.copyWith(isLoading: true, clearMessage: true));

    try {
      final events = await _localDataSource.getEventsForDate(companyDate);
      final recentEvents = await _localDataSource.getRecentEvents();

      // Show local events immediately; stay loading while the server
      // history is pulled so a check-in cannot race the import.
      emit(state.copyWith(events: events, recentEvents: recentEvents));
    } catch (_) {
      emit(state.copyWith(isLoading: false, message: 'Could not load local attendance.', messageIsError: true));
      return;
    }

    try {
      // One pull covers today's events and the recent history.
      await _syncCoordinator.pullRecentHistory(companyDate);
    } catch (_) {
      // Offline, HTTP error or malformed server data: keep the local events.
      // Part of the history may still have been imported, so reload below.
    }

    try {
      final events = await _localDataSource.getEventsForDate(companyDate);
      final recentEvents = await _localDataSource.getRecentEvents();

      emit(state.copyWith(events: events, recentEvents: recentEvents, isLoading: false));
    } catch (_) {
      emit(state.copyWith(isLoading: false));
    }
  }

  // Keeps the last known history if SQLite cannot be read.
  Future<List<AttendanceEvent>> _recentEventsOrCurrent() async {
    try {
      return await _localDataSource.getRecentEvents();
    } catch (_) {
      return state.recentEvents;
    }
  }

  Future<void> recordAttendance({required String employeeId, required AttendanceEventType type, required OfficeLocation office}) async {
    if (state.isActionInProgress) return;

    emit(state.copyWith(isActionInProgress: true, clearMessage: true));


    try {
      // The service dates the event from its own timestamp, after the GPS fix.
      final savedEvent = await _attendanceService.recordAttendance(employeeId: employeeId, type: type, office: office);

      // A transient sync failure must not undo the locally saved event;
      // it simply stays PENDING and is reported below.
      try {
        await _syncCoordinator.syncPendingEvents();
      } catch (_) {}

      var events = await _localDataSource.getEventsForDate(CompanyClock.today());

      // Report the outcome of this event, not of the sync call: a server
      // rejection is recorded on the event and does not throw.
      final finalEvent = events.where((event) => event.eventId == savedEvent.eventId).firstOrNull;

      // A duplicate means another device already recorded this action, so
      // import the server's events to show it. The rejection is still reported.
      if (finalEvent?.status == AttendanceSyncStatus.rejected && _duplicateRejectReasons.contains(finalEvent?.rejectReason)) {
        try {
          await _syncCoordinator.pullEventsForDate(savedEvent.companyDate);
          events = await _localDataSource.getEventsForDate(CompanyClock.today());
        } catch (_) {
          // Keep the rejected event and its message; history can be pulled later.
        }
      }

      final (message, isError) = switch (finalEvent?.status) {
        AttendanceSyncStatus.synced => ('Attendance saved successfully.', false),
        AttendanceSyncStatus.rejected => (finalEvent?.rejectReason ?? 'Attendance event rejected by server.', true),
        _ => ('Saved on this device. Sync is pending; try again when connected.', false),
      };

      emit(state.copyWith(events: events, recentEvents: await _recentEventsOrCurrent(), isActionInProgress: false, message: message, messageIsError: isError));
    } catch (error) {
      // Reload because the event may already exist even if a later step failed.
      List<AttendanceEvent> events = state.events;
      try {
        events = await _localDataSource.getEventsForDate(CompanyClock.today());
      } catch (_) {
        // Preserve the last known list if SQLite cannot be read.
      }

      emit(state.copyWith(events: events, recentEvents: await _recentEventsOrCurrent(), isActionInProgress: false, message: error.toString(), messageIsError: true));
    }
  }

  // Manual "Sync Now".
  Future<void> retrySync() => _syncPendingEvents(isAutomatic: false);

  // Called at startup and when connectivity returns. It stays quiet when
  // nothing is pending or the server cannot be reached.
  Future<void> syncAutomatically() => _syncPendingEvents(isAutomatic: true);

  // Runs the startup sync and starts listening for connectivity changes.
  Future<void> startAutoSync() async {
    _connectivitySubscription ??= _connectivityChanges?.listen(_onConnectivityChanged);

    await loadToday();
    await syncAutomatically();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((result) => result != ConnectivityResult.none);
    // Only a change from offline to online triggers a sync; startup is
    // handled by startAutoSync. A connection does not guarantee internet
    // access, so the sync request itself remains the real test.
    final cameOnline = isOnline && _wasOnline == false;
    _wasOnline = isOnline;

    if (cameOnline) {
      syncAutomatically();
    }
  }

  Future<void> _syncPendingEvents({required bool isAutomatic}) async {
    // Shared with recordAttendance, so only one sync or action runs at a time.
    if (state.isActionInProgress) return;

    emit(state.copyWith(isActionInProgress: true, clearMessage: !isAutomatic));

    try {
      final pendingEventIds = (await _localDataSource.getPendingEvents()).map((event) => event.eventId).toSet();

      if (isAutomatic && pendingEventIds.isEmpty) {
        emit(state.copyWith(isActionInProgress: false));
        return;
      }

      await _syncCoordinator.syncPendingEvents();

      // Check every retried event, including ones from earlier company dates.
      final retriedEvents = (await _localDataSource.getAllEvents()).where((event) => pendingEventIds.contains(event.eventId)).toList();
      final hasRejected = retriedEvents.any((event) => event.status == AttendanceSyncStatus.rejected);
      final hasPending = retriedEvents.any((event) => event.status == AttendanceSyncStatus.pending);

      final events = await _localDataSource.getEventsForDate(CompanyClock.today());

      if (isAutomatic && hasPending && !hasRejected) {
        // Still offline or the server is busy; the pending banner stays visible.
        emit(state.copyWith(events: events, recentEvents: await _recentEventsOrCurrent(), isActionInProgress: false));
        return;
      }

      final (message, isError) = hasRejected
          ? ('Sync finished, but some attendance events were rejected by the server.', true)
          : hasPending
          ? ('Some attendance events are still pending sync; try again when connected.', false)
          : ('Attendance sync completed.', false);

      emit(state.copyWith(events: events, recentEvents: await _recentEventsOrCurrent(), isActionInProgress: false, message: message, messageIsError: isError));
    } catch (_) {
      // Network errors leave events PENDING; nothing is deleted or resent here.
      List<AttendanceEvent> events = state.events;
      try {
        events = await _localDataSource.getEventsForDate(CompanyClock.today());
      } catch (_) {
        // Preserve the last known list if SQLite cannot be read.
      }

      if (isAutomatic) {
        emit(state.copyWith(events: events, recentEvents: await _recentEventsOrCurrent(), isActionInProgress: false));
        return;
      }

      emit(
        state.copyWith(
          events: events,
          recentEvents: await _recentEventsOrCurrent(),
          isActionInProgress: false,
          message: 'Sync failed. Your pending events remain saved locally.',
          messageIsError: true,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _connectivitySubscription?.cancel();
    return super.close();
  }
}
