import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/attendance/data/attendance_local_data_source.dart';
import 'package:frontend/features/attendance/data/attendance_sync_coordinator.dart';
import 'package:frontend/features/attendance/domain/attendance_event.dart';

import 'test_database.dart';

void main() {
  late AttendanceLocalDataSource localDataSource;
  late AttendanceSyncCoordinator coordinator;
  late ApiClient apiClient;
  late Dio dio;
  late dynamic testDatabase;

  setUp(() async {
    final appDatabase = await createTestDatabase();
    testDatabase = appDatabase;

    localDataSource = AttendanceLocalDataSource(appDatabase);

    apiClient = ApiClient();
    dio = apiClient.dio;

    dio.options.baseUrl = 'http://localhost:3000/api/';

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['testRequest'] = true;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 201,
              data: {'eventId': options.data['eventId']},
            ),
          );
        },
      ),
    );

    coordinator = AttendanceSyncCoordinator(
      localDataSource: localDataSource,
      apiClient: apiClient,
    );
  });

  tearDown(() async {
    await testDatabase.close();
  });

  test('successful sync marks the event as synced', () async {
    final event = AttendanceEvent(
      eventId: 'sync-test-001',
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
    );

    await localDataSource.saveEvent(event);

    await coordinator.syncPendingEvents();

    final events = await localDataSource.getAllEvents();

    expect(events, hasLength(1));
    expect(events.first.status, AttendanceSyncStatus.synced);
    expect(events.first.attemptCount, 1);
  });

  test('server validation rejection marks event as rejected', () async {
    dio.interceptors.clear();

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 422,
                data: {
                  'message': 'Outside office geofence',
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    final event = AttendanceEvent(
      eventId: 'sync-test-002',
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 13.0000,
      longitude: 77.6000,
      accuracyMeters: 10,
    );

    await localDataSource.saveEvent(event);

    await coordinator.syncPendingEvents();

    final events = await localDataSource.getAllEvents();

    expect(events, hasLength(1));
    expect(events.first.status, AttendanceSyncStatus.rejected);
    expect(events.first.rejectReason, 'Outside office geofence');
    expect(events.first.attemptCount, 1);
  });

  test('timeout keeps event pending for a safe retry', () async {
    dio.interceptors.clear();

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
              message: 'Simulated timeout',
            ),
          );
        },
      ),
    );

    const originalEventId = 'sync-test-timeout-001';

    final event = AttendanceEvent(
      eventId: originalEventId,
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
    );

    await localDataSource.saveEvent(event);

    await expectLater(
      coordinator.syncPendingEvents(),
      throwsA(isA<DioException>()),
    );

    final events = await localDataSource.getAllEvents();

    expect(events, hasLength(1));
    expect(events.first.status, AttendanceSyncStatus.pending);
    expect(events.first.eventId, originalEventId);
    expect(events.first.attemptCount, 1);
  });

  test('rejected check-in rejects queued checkout without sending it', () async {
    dio.interceptors.clear();

    var requestCount = 0;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;

          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 422,
                data: {'message': 'Check-in rejected by server'},
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    final checkIn = AttendanceEvent(
      eventId: 'dependency-check-in-001',
      employeeId: 'EMP001',
      type: AttendanceEventType.checkIn,
      occurredAt: DateTime.utc(2026, 10, 28, 9),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
    );

    final checkOut = AttendanceEvent(
      eventId: 'dependency-check-out-001',
      employeeId: 'EMP001',
      type: AttendanceEventType.checkOut,
      occurredAt: DateTime.utc(2026, 10, 28, 17),
      companyDate: '2026-10-28',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
    );

    await localDataSource.saveEvent(checkIn);
    await localDataSource.saveEvent(checkOut);

    await coordinator.syncPendingEvents();

    final events = await localDataSource.getAllEvents();

    expect(requestCount, 1);
    expect(events[0].status, AttendanceSyncStatus.rejected);
    expect(events[1].status, AttendanceSyncStatus.rejected);
    expect(
      events[1].rejectReason,
      'Checkout rejected because its check-in was rejected.',
    );
  });

  group('pullEventsForDate', () {
    Map<String, Object?> serverRecord({
      required String eventId,
      String type = 'CHECK_IN',
      String occurredAt = '2026-10-28T04:12:33.123Z',
      String companyDate = '2026-10-28',
    }) {
      return {
        'id': 'ATT-$eventId',
        'eventId': eventId,
        'employeeId': 'EMP001',
        'type': type,
        'occurredAt': occurredAt,
        'companyDate': companyDate,
        'latitude': 11.190723,
        'longitude': 75.950761,
        'status': 'SYNCED',
      };
    }

    // Replaces the default POST stub with a GET history response.
    List<RequestOptions> respondWithHistory(Object? body) {
      final requests = <RequestOptions>[];

      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: body),
            );
          },
        ),
      );

      return requests;
    }

    test('imports server events for the date as synced', () async {
      final requests = respondWithHistory({
        'month': '2026-10',
        'records': [
          {...serverRecord(eventId: 'android-001'), 'latitude': 11, 'longitude': 75},
        ],
      });

      await coordinator.pullEventsForDate('2026-10-28');

      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.path, 'attendance');
      expect(requests.single.queryParameters, {'month': '2026-10'});

      final events = await localDataSource.getAllEvents();

      expect(events, hasLength(1));
      expect(events.single.eventId, 'android-001');
      expect(events.single.employeeId, 'EMP001');
      expect(events.single.type, AttendanceEventType.checkIn);
      expect(events.single.occurredAt, DateTime.utc(2026, 10, 28, 4, 12, 33, 123));
      expect(events.single.companyDate, '2026-10-28');
      expect(events.single.latitude, 11.0);
      expect(events.single.longitude, 75.0);
      expect(events.single.accuracyMeters, 0);
      expect(events.single.status, AttendanceSyncStatus.synced);
    });

    test('ignores records from other dates', () async {
      respondWithHistory({
        'month': '2026-10',
        'records': [
          serverRecord(eventId: 'today-check-out', type: 'CHECK_OUT', occurredAt: '2026-10-28T12:30:00.000Z'),
          serverRecord(eventId: 'today-check-in'),
          serverRecord(eventId: 'yesterday-check-in', occurredAt: '2026-10-27T03:30:00.000Z', companyDate: '2026-10-27'),
        ],
      });

      await coordinator.pullEventsForDate('2026-10-28');

      final events = await localDataSource.getAllEvents();

      expect(events.map((event) => event.eventId), unorderedEquals(['today-check-out', 'today-check-in']));
    });

    test('empty history completes without changing local events', () async {
      await localDataSource.saveEvent(
        AttendanceEvent(
          eventId: 'local-pending-001',
          employeeId: 'EMP001',
          type: AttendanceEventType.checkIn,
          occurredAt: DateTime.utc(2026, 10, 28, 4),
          companyDate: '2026-10-28',
          latitude: 11.190723,
          longitude: 75.950761,
          accuracyMeters: 10,
        ),
      );
      respondWithHistory({'month': '2026-10', 'records': []});

      await coordinator.pullEventsForDate('2026-10-28');

      final events = await localDataSource.getAllEvents();

      expect(events, hasLength(1));
      expect(events.single.eventId, 'local-pending-001');
      expect(events.single.status, AttendanceSyncStatus.pending);
    });

    test('malformed envelope throws and imports nothing', () async {
      respondWithHistory({'month': '2026-10'});

      await expectLater(coordinator.pullEventsForDate('2026-10-28'), throwsA(isA<FormatException>()));

      expect(await localDataSource.getAllEvents(), isEmpty);
    });

    test('malformed record throws and imports nothing', () async {
      respondWithHistory({
        'month': '2026-10',
        'records': [
          serverRecord(eventId: 'valid-001'),
          {...serverRecord(eventId: 'invalid-001', type: 'CHECK_OUT'), 'occurredAt': 'not-a-date'},
        ],
      });

      await expectLater(coordinator.pullEventsForDate('2026-10-28'), throwsA(isA<FormatException>()));

      expect(await localDataSource.getAllEvents(), isEmpty);
    });

    test('HTTP and network failures propagate', () async {
      final failures = [
        DioExceptionType.badResponse,
        DioExceptionType.connectionError,
      ];

      for (final failure in failures) {
        dio.interceptors.clear();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: failure,
                  response: failure == DioExceptionType.badResponse
                      ? Response(requestOptions: options, statusCode: 500, data: {'code': 'MOCK_SERVER_ERROR'})
                      : null,
                ),
              );
            },
          ),
        );

        await expectLater(coordinator.pullEventsForDate('2026-10-28'), throwsA(isA<DioException>()));
      }

      expect(await localDataSource.getAllEvents(), isEmpty);
    });

    test('overlapping calls share one request', () async {
      var requestCount = 0;

      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requestCount++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'month': '2026-10',
                  'records': [serverRecord(eventId: 'android-001')],
                },
              ),
            );
          },
        ),
      );

      await Future.wait([
        coordinator.pullEventsForDate('2026-10-28'),
        coordinator.pullEventsForDate('2026-10-28'),
      ]);

      expect(requestCount, 1);
      expect(await localDataSource.getAllEvents(), hasLength(1));

      // A later call is not shared with the finished one.
      await coordinator.pullEventsForDate('2026-10-28');

      expect(requestCount, 2);
      expect(await localDataSource.getAllEvents(), hasLength(1));
    });
  });
}