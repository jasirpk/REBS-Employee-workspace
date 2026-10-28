import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/time/company_clock.dart';
import 'package:frontend/features/attendance/data/attendance_local_data_source.dart';
import 'package:frontend/features/attendance/data/attendance_sync_coordinator.dart';
import 'package:frontend/features/attendance/data/device_location_service.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';
import 'package:frontend/features/attendance/domain/attendance_location.dart';
import 'package:frontend/features/attendance/domain/attendance_service.dart';
import 'package:frontend/features/attendance/domain/office_location.dart';
import 'package:frontend/features/attendance/presentation/attendance_cubit.dart';

import 'test_database.dart';

class MockDeviceLocationService extends Mock implements DeviceLocationService {}

// Mirrors the attendance rules in backend/src/server.ts: a repeated eventId
// returns the stored record, and each day allows one check-in and one
// check-out.
class FakeAttendanceServer {
  final List<Map<String, dynamic>> records = [];
  final List<Map<String, dynamic>> receivedEvents = [];
  // Event IDs that are stored but answered with a timeout, once each.
  final Set<String> timeoutAfterAccepting = {};
  // When set, every request waits for it before being answered.
  Completer<void>? gate;

  void attachTo(Dio dio) {
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final event = Map<String, dynamic>.from(options.data as Map);
          receivedEvents.add(event);

          if (gate != null) await gate!.future;

          final (statusCode, body) = _handle(event);

          if (timeoutAfterAccepting.remove(event['eventId'])) {
            handler.reject(DioException(requestOptions: options, type: DioExceptionType.receiveTimeout));
            return;
          }

          if (statusCode >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: options, statusCode: statusCode, data: body),
              ),
            );
            return;
          }

          handler.resolve(Response(requestOptions: options, statusCode: statusCode, data: body));
        },
      ),
    );
  }

  (int, Map<String, dynamic>) _handle(Map<String, dynamic> event) {
    final existing = records.where((record) => record['eventId'] == event['eventId']).firstOrNull;
    if (existing != null) {
      // Like the backend, a reused eventId must carry the same payload,
      // compared against the stored (millisecond) timestamp.
      final samePayload = existing['type'] == event['type'] && existing['occurredAt'] == event['occurredAt'];
      if (!samePayload) {
        return (409, {'code': 'IDEMPOTENCY_KEY_REUSED', 'message': 'This event ID was already used for another payload'});
      }
      return (200, existing);
    }

    final dayRecords = records.where((record) => record['companyDate'] == event['companyDate']);
    final hasCheckIn = dayRecords.any((record) => record['type'] == 'CHECK_IN');
    final hasCheckOut = dayRecords.any((record) => record['type'] == 'CHECK_OUT');

    if (event['type'] == 'CHECK_IN' && hasCheckIn) {
      return (409, {'code': 'ATTENDANCE_ALREADY_EXISTS', 'message': 'A check-in already exists for this day'});
    }
    if (event['type'] == 'CHECK_OUT' && !hasCheckIn) {
      return (422, {'code': 'CHECK_IN_REQUIRED', 'message': 'Check-in is required before check-out'});
    }
    if (event['type'] == 'CHECK_OUT' && hasCheckOut) {
      return (409, {'code': 'ATTENDANCE_ALREADY_EXISTS', 'message': 'A check-out already exists for this day'});
    }

    // The backend stores new Date(occurredAt).toISOString(), which keeps
    // only milliseconds.
    final occurredAt = DateTime.parse(event['occurredAt'] as String).toUtc();
    final record = {
      ...event,
      'occurredAt': DateTime.fromMillisecondsSinceEpoch(occurredAt.millisecondsSinceEpoch, isUtc: true).toIso8601String(),
    };

    records.add(record);
    return (201, record);
  }
}

void main() {
  const office = OfficeLocation(latitude: 11.190723, longitude: 75.950761);
  final today = CompanyClock.today();

  late AppDatabase appDatabase;
  late AttendanceLocalDataSource localDataSource;
  late ApiClient apiClient;
  late FakeAttendanceServer server;
  late AttendanceSyncCoordinator coordinator;

  AttendanceEvent pendingEvent(String eventId, AttendanceEventType type, {int hour = 4}) {
    return AttendanceEvent(
      eventId: eventId,
      employeeId: 'EMP001',
      type: type,
      occurredAt: DateTime.utc(2026, 10, 29, hour),
      companyDate: '2026-10-29',
      latitude: office.latitude,
      longitude: office.longitude,
      accuracyMeters: 10,
    );
  }

  Future<AttendanceEvent> storedEvent(String eventId) async {
    return (await localDataSource.getAllEvents()).singleWhere((event) => event.eventId == eventId);
  }

  setUp(() async {
    appDatabase = await createTestDatabase();
    localDataSource = AttendanceLocalDataSource(appDatabase);
    apiClient = ApiClient();
    server = FakeAttendanceServer()..attachTo(apiClient.dio);
    coordinator = AttendanceSyncCoordinator(localDataSource: localDataSource, apiClient: apiClient);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('recording attendance', () {
    late MockDeviceLocationService locationService;
    late AttendanceCubit cubit;

    setUp(() {
      locationService = MockDeviceLocationService();
      when(() => locationService.getCurrentLocation()).thenAnswer(
        (_) async => AttendanceLocation(latitude: office.latitude, longitude: office.longitude, accuracyMeters: 10),
      );

      cubit = AttendanceCubit(
        localDataSource: localDataSource,
        attendanceService: AttendanceService(localDataSource: localDataSource, locationService: locationService),
        syncCoordinator: coordinator,
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test('checkout without check-in is rejected before anything is saved or sent', () async {
      await cubit.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkOut, office: office);

      expect(cubit.state.message, 'You must check in before checking out.');
      expect(cubit.state.messageIsError, isTrue);
      expect(await localDataSource.getAllEvents(), isEmpty);
      expect(server.receivedEvents, isEmpty);
    });

    test('repeated check-in taps create one event and one server record', () async {
      await Future.wait([
        cubit.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office),
        cubit.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office),
      ]);

      // A later tap is blocked by the local rule.
      await cubit.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office);

      final events = await localDataSource.getEventsForDate(today);
      expect(events, hasLength(1));
      expect(events.single.status, AttendanceSyncStatus.synced);
      expect(server.records, hasLength(1));
      expect(cubit.state.message, 'You have already checked in today.');
    });
  });

  test('pending events survive closing the database and sync in order', () async {
    final directory = await Directory.systemTemp.createTemp('attendance_persistence');
    final path = p.join(directory.path, 'attendance.db');

    Future<AppDatabase> openFileDatabase() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 3, onCreate: (db, version) => AppDatabase.createTables(db)),
      );
      return AppDatabase(databaseOpener: () async => db);
    }

    try {
      final firstRun = await openFileDatabase();
      final firstDataSource = AttendanceLocalDataSource(firstRun);
      await firstDataSource.saveEvent(pendingEvent('offline-check-in', AttendanceEventType.checkIn, hour: 4));
      await firstDataSource.saveEvent(pendingEvent('offline-check-out', AttendanceEventType.checkOut, hour: 12));
      await firstRun.close();

      // Simulates restarting the app.
      final secondRun = await openFileDatabase();
      final secondDataSource = AttendanceLocalDataSource(secondRun);

      final pending = await secondDataSource.getPendingEvents();
      expect(pending.map((event) => event.eventId), ['offline-check-in', 'offline-check-out']);

      await AttendanceSyncCoordinator(localDataSource: secondDataSource, apiClient: apiClient).syncPendingEvents();

      expect(server.receivedEvents.map((event) => event['type']), ['CHECK_IN', 'CHECK_OUT']);
      final synced = await secondDataSource.getAllEvents();
      expect(synced.every((event) => event.status == AttendanceSyncStatus.synced), isTrue);

      await secondRun.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('retrying after a timeout reuses the event identity and creates no duplicate', () async {
    // Device clocks have microsecond precision; the server keeps milliseconds.
    await localDataSource.saveEvent(
      AttendanceEvent(
        eventId: 'accepted-then-timed-out',
        employeeId: 'EMP001',
        type: AttendanceEventType.checkIn,
        occurredAt: DateTime.utc(2026, 10, 29, 4, 12, 33, 123, 456),
        companyDate: '2026-10-29',
        latitude: office.latitude,
        longitude: office.longitude,
        accuracyMeters: 10,
      ),
    );
    server.timeoutAfterAccepting.add('accepted-then-timed-out');

    await expectLater(coordinator.syncPendingEvents(), throwsA(isA<DioException>()));

    // The server stored it, but the client still treats it as pending.
    expect(server.records, hasLength(1));
    expect((await storedEvent('accepted-then-timed-out')).status, AttendanceSyncStatus.pending);

    await coordinator.syncPendingEvents();

    final event = await storedEvent('accepted-then-timed-out');
    expect(event.status, AttendanceSyncStatus.synced);
    expect(event.attemptCount, 2);
    expect(server.records, hasLength(1));
    expect(server.receivedEvents, hasLength(2));
    expect(server.receivedEvents[0], server.receivedEvents[1]);
  });

  test('overlapping sync calls send each event once', () async {
    await localDataSource.saveEvent(pendingEvent('overlap-check-in', AttendanceEventType.checkIn, hour: 4));
    await localDataSource.saveEvent(pendingEvent('overlap-check-out', AttendanceEventType.checkOut, hour: 12));
    server.gate = Completer<void>();

    final first = coordinator.syncPendingEvents();
    final second = coordinator.syncPendingEvents();

    server.gate!.complete();
    await Future.wait([first, second]);

    expect(server.receivedEvents.map((event) => event['eventId']), ['overlap-check-in', 'overlap-check-out']);
    expect(server.records, hasLength(2));
  });

  test('a rejected event stays rejected and is not sent again', () async {
    // Another device already checked in for this day.
    server.records.add({'eventId': 'android-check-in', 'type': 'CHECK_IN', 'companyDate': '2026-10-29'});
    await localDataSource.saveEvent(pendingEvent('simulator-check-in', AttendanceEventType.checkIn));

    await coordinator.syncPendingEvents();
    await coordinator.syncPendingEvents();

    final event = await storedEvent('simulator-check-in');
    expect(event.status, AttendanceSyncStatus.rejected);
    expect(event.rejectReason, 'A check-in already exists for this day');
    expect(server.receivedEvents, hasLength(1));
    expect(server.records, hasLength(1));
  });
}
