import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/dashboard/data/dashboard_local_data_source.dart';
import 'package:frontend/features/dashboard/data/dashboard_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late ApiClient apiClient;
  late DashboardRepository repository;

  final employeeJson = {
    'id': 'EMP001',
    'name': 'Alex Johnson',
    'department': 'Engineering',
    'office': {'latitude': 11.190723, 'longitude': 75.950761, 'radiusMeters': 200},
    'timezone': 'Asia/Kolkata',
  };

  final balanceJson = {'employeeId': 'EMP001', 'casual': 8, 'sick': 6};

  setUp(() async {
    appDatabase = await createTestDatabase();
    apiClient = ApiClient();
    repository = DashboardRepository(apiClient, DashboardLocalDataSource(appDatabase));
  });

  tearDown(() async {
    await appDatabase.close();
  });

  // Answers each path from [responses]; anything else fails like an offline device.
  void stubServer(Map<String, Object> responses) {
    apiClient.dio.interceptors.clear();
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = responses[options.path];

          if (data == null) {
            handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
            return;
          }

          handler.resolve(Response(requestOptions: options, statusCode: 200, data: data));
        },
      ),
    );
  }

  test('caches the employee and leave balance after successful responses', () async {
    stubServer({'employee/me': employeeJson, 'leave/balance': balanceJson});

    await repository.fetchEmployee();
    await repository.fetchLeaveBalance();

    final cached = await repository.getCachedDashboard();

    expect(cached, isNotNull);
    expect(cached!.employee.id, 'EMP001');
    expect(cached.employee.name, 'Alex Johnson');
    expect(cached.employee.department, 'Engineering');
    expect(cached.employee.timezone, 'Asia/Kolkata');
    expect(cached.employee.officeLatitude, 11.190723);
    expect(cached.employee.officeRadiusMeters, 200);
    expect(cached.leaveBalance['casual'], 8);
    expect(cached.leaveBalance['sick'], 6);
  });

  test('keeps the cache when later requests fail', () async {
    stubServer({'employee/me': employeeJson, 'leave/balance': balanceJson});
    await repository.fetchEmployee();
    await repository.fetchLeaveBalance();

    stubServer({});
    await expectLater(repository.fetchEmployee(), throwsA(isA<DioException>()));
    await expectLater(repository.fetchLeaveBalance(), throwsA(isA<DioException>()));

    final cached = await repository.getCachedDashboard();

    expect(cached!.employee.name, 'Alex Johnson');
    expect(cached.leaveBalance['casual'], 8);
  });

  test('does not cache a malformed leave balance', () async {
    stubServer({'employee/me': employeeJson, 'leave/balance': balanceJson});
    await repository.fetchEmployee();
    await repository.fetchLeaveBalance();

    stubServer({'leave/balance': {'casual': 'eight'}});
    await expectLater(repository.fetchLeaveBalance(), throwsA(isA<FormatException>()));

    final cached = await repository.getCachedDashboard();
    expect(cached!.leaveBalance['casual'], 8);
  });

  test('returns no cached dashboard until both responses are saved', () async {
    expect(await repository.getCachedDashboard(), isNull);

    stubServer({'employee/me': employeeJson});
    await repository.fetchEmployee();

    expect(await repository.getCachedDashboard(), isNull);
  });
}
