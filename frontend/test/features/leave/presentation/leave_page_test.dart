import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/features/dashboard/domain/employee.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_cubit.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_state.dart';
import 'package:frontend/features/leave/domain/leave_request.dart';
import 'package:frontend/features/leave/presentation/leave_cubit.dart';
import 'package:frontend/features/leave/presentation/leave_page.dart';
import 'package:frontend/features/leave/presentation/leave_state.dart';

class MockLeaveCubit extends MockCubit<LeaveState> implements LeaveCubit {}

class MockDashboardCubit extends MockCubit<DashboardState> implements DashboardCubit {}

void main() {
  late MockLeaveCubit leaveCubit;
  late MockDashboardCubit dashboardCubit;

  LeaveRequest leaveRequest(String id, LeaveStatus status) {
    return LeaveRequest(
      id: id,
      employeeId: 'EMP001',
      type: LeaveType.sick,
      startDate: '2026-11-02',
      endDate: '2026-11-03',
      days: 2,
      reason: 'Medical appointment and recovery',
      status: status,
      createdAt: DateTime.utc(2026, 10, 28, 9),
    );
  }

  setUp(() {
    leaveCubit = MockLeaveCubit();
    dashboardCubit = MockDashboardCubit();

    when(() => leaveCubit.loadRequests()).thenAnswer((_) async {});
    whenListen(
      dashboardCubit,
      const Stream<DashboardState>.empty(),
      initialState: const DashboardLoaded(
        employee: Employee(
          id: 'EMP001',
          name: 'Alex Johnson',
          department: 'Engineering',
          timezone: 'Asia/Kolkata',
          officeLatitude: 11.190723,
          officeLongitude: 75.950761,
          officeRadiusMeters: 200,
        ),
        casualBalance: 8,
        sickBalance: 6,
      ),
    );
  });

  Future<void> pumpLeavePage(WidgetTester tester, LeaveState state) async {
    whenListen(leaveCubit, const Stream<LeaveState>.empty(), initialState: state);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<LeaveCubit>.value(value: leaveCubit),
            BlocProvider<DashboardCubit>.value(value: dashboardCubit),
          ],
          child: const LeavePage(),
        ),
      ),
    );
  }

  testWidgets('loads requests and shows the form with the balance', (tester) async {
    await pumpLeavePage(tester, const LeaveState(hasLoaded: true));

    verify(() => leaveCubit.loadRequests()).called(1);
    expect(find.text('Available: 8 casual, 6 sick days'), findsOneWidget);
    expect(find.text('Submit Request'), findsOneWidget);
    expect(find.text('You have not applied for leave yet.'), findsOneWidget);
  });

  testWidgets('shows a distinct message when offline with no saved requests', (tester) async {
    await pumpLeavePage(tester, const LeaveState(hasLoaded: true, isFromCache: true));

    expect(find.text('You are offline and no leave requests are saved on this device yet.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows cached requests with their statuses and an offline banner', (tester) async {
    await pumpLeavePage(
      tester,
      LeaveState(
        hasLoaded: true,
        isFromCache: true,
        requests: [
          leaveRequest('LEAVE001', LeaveStatus.pending),
          leaveRequest('LEAVE002', LeaveStatus.approved),
          leaveRequest('LEAVE003', LeaveStatus.rejected),
        ],
      ),
    );
    // The reason TextField has its own Scrollable, so name the list's one.
    await tester.scrollUntilVisible(
      find.text('Rejected'),
      200,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );

    expect(find.textContaining('Offline. Showing leave requests saved on this device.'), findsOneWidget);
    expect(find.text('Sick leave · 2 days'), findsNWidgets(3));
    expect(find.text('2 Nov 2026 – 3 Nov 2026'), findsNWidgets(3));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('shows a validation message and a disabled button while submitting', (tester) async {
    await pumpLeavePage(
      tester,
      const LeaveState(hasLoaded: true, isSubmitting: true, message: 'Simulated leave validation rejection', messageIsError: true),
    );

    expect(find.text('Simulated leave validation rejection'), findsOneWidget);
    final submitButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submitButton.onPressed, isNull);
  });
}
