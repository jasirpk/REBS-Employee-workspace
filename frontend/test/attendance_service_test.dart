import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

import 'test_database.dart';

class MockDeviceLocationService extends Mock implements DeviceLocationService {}

void main() {
  const office = OfficeLocation(latitude: 11.190723, longitude: 75.950761);

  // 23:59:58 and 00:00:05 company time (UTC+05:30), either side of midnight.
  final beforeMidnight = DateTime.utc(2026, 10, 28, 18, 29, 58);
  final afterMidnight = DateTime.utc(2026, 10, 28, 18, 30, 5);

  late AppDatabase appDatabase;
  late AttendanceLocalDataSource localDataSource;
  late MockDeviceLocationService locationService;
  late DateTime now;
  late AttendanceService service;

  setUp(() async {
    appDatabase = await createTestDatabase();
    localDataSource = AttendanceLocalDataSource(appDatabase);
    locationService = MockDeviceLocationService();
    now = beforeMidnight;
    service = AttendanceService(localDataSource: localDataSource, locationService: locationService, clock: () => now);

    // The GPS fix arrives after midnight.
    when(() => locationService.getCurrentLocation()).thenAnswer((_) async {
      now = afterMidnight;
      return AttendanceLocation(latitude: office.latitude, longitude: office.longitude, accuracyMeters: 10);
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('dates the event from its own timestamp after a GPS wait that crosses midnight', () async {
    final event = await service.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office);

    expect(event.occurredAt, afterMidnight);
    expect(event.companyDate, '2026-10-29');
    expect(event.companyDate, CompanyClock.dateOf(event.occurredAt));

    final stored = (await localDataSource.getAllEvents()).single;
    expect(stored.occurredAt, afterMidnight);
    expect(stored.companyDate, '2026-10-29');
  });

  test('checks the rules again for the new day', () async {
    // The new day already has a check-in, e.g. imported from another device.
    await localDataSource.importSyncedEvents([
      AttendanceEvent(
        eventId: 'new-day-check-in',
        employeeId: 'EMP001',
        type: AttendanceEventType.checkIn,
        occurredAt: DateTime.utc(2026, 10, 28, 18, 30, 1),
        companyDate: '2026-10-29',
        latitude: office.latitude,
        longitude: office.longitude,
        accuracyMeters: 0,
      ),
    ]);

    await expectLater(
      service.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office),
      throwsA(isA<AttendanceValidationException>().having((error) => error.message, 'message', 'You have already checked in today.')),
    );
    expect(await localDataSource.getAllEvents(), hasLength(1));
  });

  test('sync sends the stored timestamp and company date unchanged, also on retry', () async {
    await service.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office);

    final apiClient = ApiClient();
    final sentBodies = <Map<String, dynamic>>[];
    var attempt = 0;
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sentBodies.add(Map<String, dynamic>.from(options.data as Map));
          attempt++;
          // First attempt times out; the retry succeeds.
          if (attempt == 1) {
            handler.reject(DioException(requestOptions: options, type: DioExceptionType.receiveTimeout));
            return;
          }
          handler.resolve(Response(requestOptions: options, statusCode: 201, data: options.data));
        },
      ),
    );
    final coordinator = AttendanceSyncCoordinator(localDataSource: localDataSource, apiClient: apiClient);

    await expectLater(coordinator.syncPendingEvents(), throwsA(isA<DioException>()));
    await coordinator.syncPendingEvents();

    expect(sentBodies, hasLength(2));
    for (final body in sentBodies) {
      expect(body['occurredAt'], '2026-10-28T18:30:05.000Z');
      expect(body['companyDate'], '2026-10-29');
    }
    expect(sentBodies[0]['eventId'], sentBodies[1]['eventId']);
    expect((await localDataSource.getAllEvents()).single.status, AttendanceSyncStatus.synced);
  });

  test('a repeated check-in on the same day still fails before waiting for GPS', () async {
    now = afterMidnight;
    when(() => locationService.getCurrentLocation()).thenAnswer(
      (_) async => AttendanceLocation(latitude: office.latitude, longitude: office.longitude, accuracyMeters: 10),
    );
    await service.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office);
    clearInteractions(locationService);

    await expectLater(
      service.recordAttendance(employeeId: 'EMP001', type: AttendanceEventType.checkIn, office: office),
      throwsA(isA<AttendanceValidationException>()),
    );
    verifyNever(() => locationService.getCurrentLocation());
  });
}
