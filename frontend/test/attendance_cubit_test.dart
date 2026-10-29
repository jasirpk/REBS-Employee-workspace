import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/core/time/company_clock.dart';
import 'package:frontend/features/attendance/data/attendance_local_data_source.dart';
import 'package:frontend/features/attendance/data/attendance_sync_coordinator.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';
import 'package:frontend/features/attendance/domain/attendance_service.dart';
import 'package:frontend/features/attendance/domain/office_location.dart';
import 'package:frontend/features/attendance/presentation/attendance_cubit.dart';

import 'test_database.dart';

class MockAttendanceService extends Mock implements AttendanceService {}

class MockAttendanceSyncCoordinator extends Mock implements AttendanceSyncCoordinator {}

void main() {
  const office = OfficeLocation(latitude: 11.190723, longitude: 75.950761);

  late AppDatabase testDatabase;
  late AttendanceLocalDataSource localDataSource;
  late MockAttendanceService attendanceService;
  late MockAttendanceSyncCoordinator syncCoordinator;
  late AttendanceCubit cubit;

  AttendanceEvent buildEvent(String eventId) {
    return AttendanceEvent(
      eventId: eventId,
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.now().toUtc(),
      // The Cubit reloads events for the company's current day.
      companyDate: CompanyClock.today(),
      latitude: 11.190723,
      longitude: 75.950761,
      accuracyMeters: 10,
    );
  }

  // Mirrors AttendanceService: persist the event as PENDING, then return it.
  void stubRecordAttendanceSaves(AttendanceEvent event) {
    when(
      () => attendanceService.recordAttendance(
        employeeId: any(named: 'employeeId'),
        type: any(named: 'type'),
        office: any(named: 'office'),
      ),
    ).thenAnswer((_) async {
      await localDataSource.saveEvent(event);
      return event;
    });
  }

  Future<void> recordCheckIn() {
    return cubit.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office);
  }

  setUpAll(() {
    registerFallbackValue(AttendanceEventType.checkIn);
    registerFallbackValue(office);
  });

  setUp(() async {
    testDatabase = await createTestDatabase();
    localDataSource = AttendanceLocalDataSource(testDatabase);
    attendanceService = MockAttendanceService();
    syncCoordinator = MockAttendanceSyncCoordinator();

    // By default the server history is reachable but adds nothing.
    when(() => syncCoordinator.pullEventsForDate(any())).thenAnswer((_) async {});
    when(() => syncCoordinator.pullRecentHistory(any())).thenAnswer((_) async {});

    cubit = AttendanceCubit(
      localDataSource: localDataSource,
      attendanceService: attendanceService,
      syncCoordinator: syncCoordinator,
    );
  });

  tearDown(() async {
    await cubit.close();
    await testDatabase.close();
  });

  group('recordAttendance', () {
    test('synced event reports success', () async {
      final event = buildEvent('cubit-synced-001');
      stubRecordAttendanceSaves(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(eventId: event.eventId, status: AttendanceSyncStatus.synced);
      });

      await recordCheckIn();

      expect(cubit.state.message, 'Attendance saved successfully.');
      expect(cubit.state.messageIsError, isFalse);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.synced);
    });

    test('rejected event reports its rejection reason as an error', () async {
      final event = buildEvent('cubit-rejected-001');
      stubRecordAttendanceSaves(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(
          eventId: event.eventId,
          status: AttendanceSyncStatus.rejected,
          rejectReason: 'A check-in already exists for this day',
        );
      });

      await recordCheckIn();

      expect(cubit.state.message, 'A check-in already exists for this day');
      expect(cubit.state.messageIsError, isTrue);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.rejected);
    });

    test('event left pending by a sync failure reports pending sync without an error', () async {
      final event = buildEvent('cubit-pending-001');
      stubRecordAttendanceSaves(event);
      when(() => syncCoordinator.syncPendingEvents()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'attendance/events'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await recordCheckIn();

      expect(cubit.state.message, 'Saved on this device. Sync is pending; try again when connected.');
      expect(cubit.state.messageIsError, isFalse);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.pending);
    });
  });

  group('retrySync', () {
    test('reports rejection when a pending event becomes rejected', () async {
      final event = buildEvent('cubit-retry-rejected-001');
      await localDataSource.saveEvent(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(
          eventId: event.eventId,
          status: AttendanceSyncStatus.rejected,
          rejectReason: 'A check-in already exists for this day',
        );
      });

      await cubit.retrySync();

      expect(cubit.state.message, 'Sync finished, but some attendance events were rejected by the server.');
      expect(cubit.state.messageIsError, isTrue);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.rejected);
    });

    test('reports pending when an event remains pending', () async {
      final event = buildEvent('cubit-retry-pending-001');
      await localDataSource.saveEvent(event);
      // Completes without syncing, as when another sync is already running.
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {});

      await cubit.retrySync();

      expect(cubit.state.message, 'Some attendance events are still pending sync; try again when connected.');
      expect(cubit.state.messageIsError, isFalse);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.pending);
    });

    test('reports completion when every pending event is synced', () async {
      final event = buildEvent('cubit-retry-synced-001');
      await localDataSource.saveEvent(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(eventId: event.eventId, status: AttendanceSyncStatus.synced);
      });

      await cubit.retrySync();

      expect(cubit.state.message, 'Attendance sync completed.');
      expect(cubit.state.messageIsError, isFalse);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.status, AttendanceSyncStatus.synced);
    });
  });

  group('loadToday', () {
    test('shows local events and keeps them when the history pull fails', () async {
      await localDataSource.saveEvent(buildEvent('local-pending-001'));
      final pull = Completer<void>();
      when(() => syncCoordinator.pullRecentHistory(any())).thenAnswer((_) => pull.future);

      final localStateShown = cubit.stream.firstWhere((state) => state.events.isNotEmpty);
      final load = cubit.loadToday();

      // Local events are emitted before the pull finishes.
      final localState = await localStateShown;
      expect(localState.events.single.eventId, 'local-pending-001');
      expect(localState.isLoading, isTrue);

      pull.completeError(
        DioException(
          requestOptions: RequestOptions(path: 'attendance'),
          type: DioExceptionType.connectionError,
        ),
      );
      await load;

      expect(cubit.state.events.single.eventId, 'local-pending-001');
      expect(cubit.state.events.single.status, AttendanceSyncStatus.pending);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.message, isNull);
      verify(() => syncCoordinator.pullRecentHistory(CompanyClock.today())).called(1);
    });

    test('includes a server event after a successful pull', () async {
      when(() => syncCoordinator.pullRecentHistory(any())).thenAnswer((_) async {
        await localDataSource.importSyncedEvents([buildEvent('android-001')]);
      });

      await cubit.loadToday();

      expect(cubit.state.events.single.eventId, 'android-001');
      expect(cubit.state.events.single.status, AttendanceSyncStatus.synced);
      expect(cubit.state.isLoading, isFalse);
    });

    test('overlapping calls share one history pull', () async {
      final pull = Completer<void>();
      when(() => syncCoordinator.pullRecentHistory(any())).thenAnswer((_) => pull.future);

      final first = cubit.loadToday();
      final second = cubit.loadToday();

      pull.complete();
      await Future.wait([first, second]);

      verify(() => syncCoordinator.pullRecentHistory(any())).called(1);
      expect(cubit.state.isLoading, isFalse);

      // A later call pulls again.
      await cubit.loadToday();

      verify(() => syncCoordinator.pullRecentHistory(any())).called(1);
    });

    test('keeps cached history from earlier dates when the pull fails', () async {
      await localDataSource.saveEvent(
        AttendanceEvent(
          eventId: 'cached-yesterday',
          employeeId: 'EMP001',
          type: AttendanceEventType.checkOut,
          occurredAt: DateTime.utc(2026, 10, 27, 12),
          companyDate: '2026-10-27',
          latitude: 11.190723,
          longitude: 75.950761,
          accuracyMeters: 10,
          status: AttendanceSyncStatus.synced,
        ),
      );
      await localDataSource.saveEvent(buildEvent('cached-today'));
      when(() => syncCoordinator.pullRecentHistory(any())).thenThrow(
        DioException(requestOptions: RequestOptions(path: 'attendance'), type: DioExceptionType.connectionError),
      );

      await cubit.loadToday();

      expect(cubit.state.recentEvents.map((event) => event.eventId), ['cached-today', 'cached-yesterday']);
      expect(cubit.state.events.single.eventId, 'cached-today');
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.message, isNull);
    });

    test('shows history imported from earlier dates after a successful pull', () async {
      when(() => syncCoordinator.pullRecentHistory(any())).thenAnswer((_) async {
        await localDataSource.importSyncedEvents([
          AttendanceEvent(
            eventId: 'server-earlier-day',
            employeeId: 'EMP001',
            type: AttendanceEventType.checkIn,
            occurredAt: DateTime.utc(2026, 10, 20, 4),
            companyDate: '2026-10-20',
            latitude: 11.190723,
            longitude: 75.950761,
            accuracyMeters: 0,
          ),
        ]);
      });

      await cubit.loadToday();

      expect(cubit.state.recentEvents.single.eventId, 'server-earlier-day');
      expect(cubit.state.events, isEmpty);
    });

    test('a new attendance action appears in the history straight away', () async {
      final event = buildEvent('cubit-history-001');
      stubRecordAttendanceSaves(event);
      when(() => syncCoordinator.syncPendingEvents()).thenThrow(
        DioException(requestOptions: RequestOptions(path: 'attendance/events'), type: DioExceptionType.connectionError),
      );

      await recordCheckIn();

      expect(cubit.state.recentEvents.single.eventId, 'cubit-history-001');
      expect(cubit.state.recentEvents.single.status, AttendanceSyncStatus.pending);
    });
  });

  group('recordAttendance duplicate rejection', () {
    void stubSyncRejects(AttendanceEvent event, String rejectReason) {
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(
          eventId: event.eventId,
          status: AttendanceSyncStatus.rejected,
          rejectReason: rejectReason,
        );
      });
    }

    test('pulls history and shows the server check-in', () async {
      final event = buildEvent('cubit-duplicate-001');
      stubRecordAttendanceSaves(event);
      stubSyncRejects(event, 'A check-in already exists for this day');
      when(() => syncCoordinator.pullEventsForDate(any())).thenAnswer((_) async {
        await localDataSource.importSyncedEvents([buildEvent('android-001')]);
      });

      await recordCheckIn();

      verify(() => syncCoordinator.pullEventsForDate(event.companyDate)).called(1);
      expect(cubit.state.message, 'A check-in already exists for this day');
      expect(cubit.state.messageIsError, isTrue);
      expect(cubit.state.isActionInProgress, isFalse);

      final statuses = {for (final event in cubit.state.events) event.eventId: event.status};
      expect(statuses, {
        'cubit-duplicate-001': AttendanceSyncStatus.rejected,
        'android-001': AttendanceSyncStatus.synced,
      });
    });

    test('does not pull history for a non-duplicate rejection', () async {
      final event = buildEvent('cubit-geofence-001');
      stubRecordAttendanceSaves(event);
      stubSyncRejects(event, 'You must be within 200 metres of the office');

      await recordCheckIn();

      verifyNever(() => syncCoordinator.pullEventsForDate(any()));
      expect(cubit.state.message, 'You must be within 200 metres of the office');
      expect(cubit.state.messageIsError, isTrue);
    });

    test('keeps the rejection when the history pull fails', () async {
      final event = buildEvent('cubit-duplicate-002');
      stubRecordAttendanceSaves(event);
      stubSyncRejects(event, 'A check-in already exists for this day');
      when(() => syncCoordinator.pullEventsForDate(any())).thenThrow(const FormatException('Attendance history response is malformed.'));

      await recordCheckIn();

      verify(() => syncCoordinator.pullEventsForDate(event.companyDate)).called(1);
      expect(cubit.state.message, 'A check-in already exists for this day');
      expect(cubit.state.messageIsError, isTrue);
      expect(cubit.state.isActionInProgress, isFalse);
      expect(cubit.state.events.single.eventId, 'cubit-duplicate-002');
      expect(cubit.state.events.single.status, AttendanceSyncStatus.rejected);
    });
  });

  group('automatic sync', () {
    late StreamController<List<ConnectivityResult>> connectivity;
    late AttendanceCubit autoSyncCubit;

    setUp(() {
      // Synchronous, so a connectivity event is handled before add() returns.
      connectivity = StreamController<List<ConnectivityResult>>(sync: true);
      autoSyncCubit = AttendanceCubit(
        localDataSource: localDataSource,
        attendanceService: attendanceService,
        syncCoordinator: syncCoordinator,
        connectivityChanges: connectivity.stream,
      );
    });

    tearDown(() async {
      await autoSyncCubit.close();
      // Not awaited: close() only completes once a listener receives the
      // done event, and some tests never subscribe.
      unawaited(connectivity.close());
    });

    Future<void> waitForIdle() {
      return autoSyncCubit.stream.firstWhere((state) => !state.isActionInProgress);
    }

    test('startup syncs pending events through the coordinator', () async {
      final event = buildEvent('auto-startup-001');
      await localDataSource.saveEvent(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(eventId: event.eventId, status: AttendanceSyncStatus.synced);
      });

      await autoSyncCubit.startAutoSync();

      verify(() => syncCoordinator.pullRecentHistory(CompanyClock.today())).called(1);
      verify(() => syncCoordinator.syncPendingEvents()).called(1);
      expect(autoSyncCubit.state.events.single.status, AttendanceSyncStatus.synced);
      expect(autoSyncCubit.state.message, 'Attendance sync completed.');
      expect(autoSyncCubit.state.isActionInProgress, isFalse);
    });

    test('startup does not call the coordinator when nothing is pending', () async {
      await autoSyncCubit.startAutoSync();

      verifyNever(() => syncCoordinator.syncPendingEvents());
      expect(autoSyncCubit.state.isActionInProgress, isFalse);
      expect(autoSyncCubit.state.message, isNull);
    });

    test('a failed startup sync stays quiet and keeps the event pending', () async {
      await localDataSource.saveEvent(buildEvent('auto-offline-001'));
      when(() => syncCoordinator.syncPendingEvents()).thenThrow(
        DioException(requestOptions: RequestOptions(path: 'attendance/events'), type: DioExceptionType.connectionError),
      );

      await autoSyncCubit.startAutoSync();

      expect(autoSyncCubit.state.events.single.status, AttendanceSyncStatus.pending);
      expect(autoSyncCubit.state.message, isNull);
      expect(autoSyncCubit.state.isActionInProgress, isFalse);
    });

    test('syncs when connectivity returns, but not on other changes', () async {
      await autoSyncCubit.startAutoSync();
      final event = buildEvent('auto-reconnect-001');
      await localDataSource.saveEvent(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(eventId: event.eventId, status: AttendanceSyncStatus.synced);
      });

      // The first event only records the current state.
      connectivity.add([ConnectivityResult.wifi]);
      expect(autoSyncCubit.state.isActionInProgress, isFalse);

      connectivity.add([ConnectivityResult.none]);
      expect(autoSyncCubit.state.isActionInProgress, isFalse);

      final idle = waitForIdle();
      connectivity.add([ConnectivityResult.mobile]);
      expect(autoSyncCubit.state.isActionInProgress, isTrue);
      await idle;

      // Switching between connected networks is not a reconnection.
      connectivity.add([ConnectivityResult.wifi]);
      expect(autoSyncCubit.state.isActionInProgress, isFalse);

      verify(() => syncCoordinator.syncPendingEvents()).called(1);
      expect(autoSyncCubit.state.events.single.status, AttendanceSyncStatus.synced);
    });

    test('a rejection during automatic sync is shown as an error', () async {
      final event = buildEvent('auto-rejected-001');
      await localDataSource.saveEvent(event);
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) async {
        await localDataSource.updateSyncStatus(
          eventId: event.eventId,
          status: AttendanceSyncStatus.rejected,
          rejectReason: 'A check-in already exists for this day',
        );
      });

      await autoSyncCubit.startAutoSync();

      expect(autoSyncCubit.state.events.single.status, AttendanceSyncStatus.rejected);
      expect(autoSyncCubit.state.message, 'Sync finished, but some attendance events were rejected by the server.');
      expect(autoSyncCubit.state.messageIsError, isTrue);
    });

    test('a sync request is ignored while another is running', () async {
      await localDataSource.saveEvent(buildEvent('auto-overlap-001'));
      final sync = Completer<void>();
      when(() => syncCoordinator.syncPendingEvents()).thenAnswer((_) => sync.future);

      // retrySync marks the cubit busy before its first await.
      final running = autoSyncCubit.retrySync();
      expect(autoSyncCubit.state.isActionInProgress, isTrue);

      await autoSyncCubit.syncAutomatically();
      await autoSyncCubit.retrySync();

      sync.complete();
      await running;

      verify(() => syncCoordinator.syncPendingEvents()).called(1);
    });

    test('closing the cubit stops listening for connectivity', () async {
      await autoSyncCubit.startAutoSync();
      expect(connectivity.hasListener, isTrue);

      await autoSyncCubit.close();

      expect(connectivity.hasListener, isFalse);
    });
  });
}
