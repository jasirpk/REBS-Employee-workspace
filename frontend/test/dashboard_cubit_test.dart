import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/features/dashboard/data/dashboard_repository.dart';
import 'package:frontend/features/dashboard/domain/employee.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_cubit.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_state.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

void main() {
  const employee = Employee(
    id: 'EMP001',
    name: 'Alex Johnson',
    department: 'Engineering',
    timezone: 'Asia/Kolkata',
    officeLatitude: 11.190723,
    officeLongitude: 75.950761,
    officeRadiusMeters: 200,
  );

  final savedAt = DateTime.utc(2026, 10, 28, 9);

  late MockDashboardRepository repository;
  late DashboardCubit cubit;

  DioException offline() {
    return DioException(requestOptions: RequestOptions(path: 'employee/me'), type: DioExceptionType.connectionError);
  }

  void stubCache(CachedDashboard? cached) {
    when(() => repository.getCachedDashboard()).thenAnswer((_) async => cached);
  }

  void stubServerOnline() {
    when(() => repository.fetchEmployee()).thenAnswer((_) async => employee);
    when(() => repository.fetchLeaveBalance()).thenAnswer((_) async => {'casual': 8, 'sick': 6});
  }

  void stubServerOffline() {
    when(() => repository.fetchEmployee()).thenAnswer((_) async => throw offline());
    when(() => repository.fetchLeaveBalance()).thenAnswer((_) async => throw offline());
  }

  setUp(() {
    repository = MockDashboardRepository();
    cubit = DashboardCubit(repository);
  });

  tearDown(() async {
    await cubit.close();
  });

  test('shows fresh server data', () async {
    stubCache(null);
    stubServerOnline();

    await cubit.loadDashboard();

    expect(
      cubit.state,
      const DashboardLoaded(employee: employee, casualBalance: 8, sickBalance: 6),
    );
  });

  test('uses the cached employee and balance after a network failure', () async {
    stubCache(CachedDashboard(employee: employee, leaveBalance: const {'casual': 5, 'sick': 2}, savedAt: savedAt));
    stubServerOffline();

    await cubit.loadDashboard();

    final state = cubit.state as DashboardLoaded;
    expect(state.employee.name, 'Alex Johnson');
    expect(state.casualBalance, 5);
    expect(state.sickBalance, 2);
    expect(state.isFromCache, isTrue);
    expect(state.savedAt, savedAt);
    expect(state.isRefreshing, isFalse);
  });

  test('shows cached data while the server refresh is running', () async {
    stubCache(CachedDashboard(employee: employee, leaveBalance: const {'casual': 5, 'sick': 2}, savedAt: savedAt));
    final employeeResponse = Completer<Employee>();
    when(() => repository.fetchEmployee()).thenAnswer((_) => employeeResponse.future);
    when(() => repository.fetchLeaveBalance()).thenAnswer((_) async => {'casual': 8, 'sick': 6});

    final cachedShown = cubit.stream.firstWhere((state) => state is DashboardLoaded);
    final load = cubit.loadDashboard();

    final cachedState = await cachedShown as DashboardLoaded;
    expect(cachedState.isFromCache, isTrue);
    expect(cachedState.isRefreshing, isTrue);

    employeeResponse.complete(employee);
    await load;

    expect(
      cubit.state,
      const DashboardLoaded(employee: employee, casualBalance: 8, sickBalance: 6),
    );
  });

  test('shows loading and then an error when there is no cache and no server', () async {
    stubCache(null);
    stubServerOffline();

    final expectedStates = expectLater(
      cubit.stream,
      emitsInOrder([
        const DashboardLoading(),
        const DashboardError(DashboardCubit.noSavedProfileMessage),
      ]),
    );

    await cubit.loadDashboard();
    await expectedStates;
  });
}
