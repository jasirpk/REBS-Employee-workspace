import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/leave/data/leave_local_data_source.dart';
import 'package:frontend/features/leave/data/leave_repository.dart';
import 'package:frontend/features/leave/domain/leave_request.dart';

import '../../../test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late LeaveLocalDataSource localDataSource;
  late ApiClient apiClient;
  late LeaveRepository repository;

  final approvedRequestJson = {
    'id': 'LEAVE001',
    'employeeId': 'EMP001',
    'type': 'CASUAL',
    'startDate': '2026-10-20',
    'endDate': '2026-10-21',
    'days': 2,
    'reason': 'Personal family commitments',
    'status': 'APPROVED',
    'createdAt': '2026-10-10T09:00:00.000Z',
  };

  setUp(() async {
    appDatabase = await createTestDatabase();
    localDataSource = LeaveLocalDataSource(appDatabase);
    apiClient = ApiClient();
    repository = LeaveRepository(apiClient: apiClient, localDataSource: localDataSource);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  // Every request succeeds with [statusCode] and [data], or fails with
  // [errorType]; a badResponse failure carries [statusCode] and [data].
  List<RequestOptions> stubServer({
    int statusCode = 200,
    Object? data,
    DioExceptionType? errorType,
  }) {
    final requests = <RequestOptions>[];

    apiClient.dio.interceptors.clear();
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);

          if (errorType != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: errorType,
                response: errorType == DioExceptionType.badResponse
                    ? Response(requestOptions: options, statusCode: statusCode, data: data)
                    : null,
              ),
            );
            return;
          }

          handler.resolve(Response(requestOptions: options, statusCode: statusCode, data: data));
        },
      ),
    );

    return requests;
  }

  group('loadLeaveRequests', () {
    test('parses the server response and caches it', () async {
      final requests = stubServer(data: {'requests': [approvedRequestJson]});

      final result = await repository.loadLeaveRequests();

      expect(requests.single.method, 'GET');
      expect(requests.single.path, 'leave/requests');
      expect(result.isFromCache, isFalse);
      expect(result.requests.single.id, 'LEAVE001');
      expect(result.requests.single.type, LeaveType.casual);
      expect(result.requests.single.status, LeaveStatus.approved);
      expect(result.requests.single.startDate, '2026-10-20');

      final cached = await localDataSource.getLeaveRequests();
      expect(cached.single.id, 'LEAVE001');
    });

    test('returns cached requests when the network request fails', () async {
      stubServer(data: {'requests': [approvedRequestJson]});
      await repository.loadLeaveRequests();

      stubServer(errorType: DioExceptionType.connectionError);
      final result = await repository.loadLeaveRequests();

      expect(result.isFromCache, isTrue);
      expect(result.requests.single.id, 'LEAVE001');
      expect(result.requests.single.status, LeaveStatus.approved);
    });

    test('keeps the cache after a failed or malformed refresh', () async {
      stubServer(data: {'requests': [approvedRequestJson]});
      await repository.loadLeaveRequests();

      stubServer(statusCode: 500, data: {'code': 'MOCK_SERVER_ERROR'}, errorType: DioExceptionType.badResponse);
      expect((await repository.loadLeaveRequests()).isFromCache, isTrue);

      stubServer(data: {'requests': [{...approvedRequestJson, 'status': 'UNKNOWN'}]});
      expect((await repository.loadLeaveRequests()).isFromCache, isTrue);

      final cached = await localDataSource.getLeaveRequests();
      expect(cached.single.id, 'LEAVE001');
      expect(cached.single.status, LeaveStatus.approved);
    });

    test('returns an empty cached list when offline before any download', () async {
      stubServer(errorType: DioExceptionType.connectionTimeout);

      final result = await repository.loadLeaveRequests();

      expect(result.isFromCache, isTrue);
      expect(result.requests, isEmpty);
    });
  });

  group('submitLeaveRequest', () {
    test('sends a valid request and caches the created request', () async {
      final requests = stubServer(
        statusCode: 201,
        data: {
          ...approvedRequestJson,
          'id': 'LEAVE002',
          'startDate': '2026-11-02',
          'endDate': '2026-11-03',
          'reason': 'Attending a family wedding',
          'status': 'PENDING',
          'createdAt': '2026-10-29T05:00:00.000Z',
        },
      );

      final created = await repository.submitLeaveRequest(
        type: LeaveType.casual,
        startDate: '2026-11-02',
        endDate: '2026-11-03',
        reason: 'Attending a family wedding',
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.path, 'leave/requests');
      expect(requests.single.data, {
        'type': 'CASUAL',
        'startDate': '2026-11-02',
        'endDate': '2026-11-03',
        'reason': 'Attending a family wedding',
      });
      expect(created.id, 'LEAVE002');
      expect(created.status, LeaveStatus.pending);

      final cached = await localDataSource.getLeaveRequests();
      expect(cached.single.id, 'LEAVE002');
    });

    test('shows the server message when validation rejects the request', () async {
      stubServer(
        statusCode: 422,
        data: {
          'code': 'LEAVE_DATE_OVERLAP',
          'message': 'Dates overlap an existing pending or approved leave request',
        },
        errorType: DioExceptionType.badResponse,
      );

      await expectLater(
        repository.submitLeaveRequest(
          type: LeaveType.casual,
          startDate: '2026-10-20',
          endDate: '2026-10-21',
          reason: 'Attending a family wedding',
        ),
        throwsA(
          isA<LeaveSubmissionException>().having(
            (error) => error.message,
            'message',
            'Dates overlap an existing pending or approved leave request',
          ),
        ),
      );

      expect(await localDataSource.getLeaveRequests(), isEmpty);
    });

    test('explains that submission needs a connection when offline', () async {
      stubServer(errorType: DioExceptionType.connectionError);

      await expectLater(
        repository.submitLeaveRequest(
          type: LeaveType.sick,
          startDate: '2026-11-02',
          endDate: '2026-11-02',
          reason: 'Medical appointment',
        ),
        throwsA(
          isA<LeaveSubmissionException>().having(
            (error) => error.message,
            'message',
            'Could not reach the server. Leave requests need an internet connection.',
          ),
        ),
      );
    });
  });
}
