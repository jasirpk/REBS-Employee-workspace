import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/features/attendance/domain/attendance_event.dart';
import 'package:frontend/features/attendance/domain/office_location.dart';
import 'package:frontend/features/attendance/presentation/attendance_cubit.dart';
import 'package:frontend/features/attendance/presentation/attendance_state.dart';
import 'package:frontend/features/dashboard/domain/employee.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_cubit.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_page.dart';
import 'package:frontend/features/dashboard/presentaion/dashboard_state.dart';
import 'package:frontend/features/leave/presentation/leave_cubit.dart';
import 'package:frontend/features/leave/presentation/leave_page.dart';
import 'package:frontend/features/leave/presentation/leave_state.dart';

class MockDashboardCubit extends MockCubit<DashboardState> implements DashboardCubit {}

class MockAttendanceCubit extends MockCubit<AttendanceState> implements AttendanceCubit {}

class MockLeaveCubit extends MockCubit<LeaveState> implements LeaveCubit {}

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

  const loadedState = DashboardLoaded(employee: employee, casualBalance: 8, sickBalance: 6);

  late MockDashboardCubit dashboardCubit;
  late MockAttendanceCubit attendanceCubit;
  late MockLeaveCubit leaveCubit;

  setUpAll(() {
    registerFallbackValue(AttendanceEventType.checkIn);
    registerFallbackValue(const OfficeLocation(latitude: 0, longitude: 0));
  });

  setUp(() {
    dashboardCubit = MockDashboardCubit();
    attendanceCubit = MockAttendanceCubit();
    leaveCubit = MockLeaveCubit();

    whenListen(attendanceCubit, const Stream<AttendanceState>.empty(), initialState: const AttendanceState());
    whenListen(leaveCubit, const Stream<LeaveState>.empty(), initialState: const LeaveState());
    when(() => leaveCubit.loadRequests()).thenAnswer((_) async {});
    when(() => dashboardCubit.loadDashboard()).thenAnswer((_) async {});
    when(() => attendanceCubit.loadToday()).thenAnswer((_) async {});
  });

  Future<void> pumpDashboard(WidgetTester tester, DashboardState state) async {
    whenListen(dashboardCubit, const Stream<DashboardState>.empty(), initialState: state);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<DashboardCubit>.value(value: dashboardCubit),
            BlocProvider<AttendanceCubit>.value(value: attendanceCubit),
            BlocProvider<LeaveCubit>.value(value: leaveCubit),
          ],
          child: const DashboardPage(),
        ),
      ),
    );
  }

  void verifyRefreshedOnceWithoutAttendanceActions() {
    verify(() => dashboardCubit.loadDashboard()).called(1);
    verify(() => attendanceCubit.loadToday()).called(1);
    verifyNever(
      () => attendanceCubit.recordAttendance(
        employeeId: any(named: 'employeeId'),
        type: any(named: 'type'),
        office: any(named: 'office'),
      ),
    );
    verifyNever(() => attendanceCubit.retrySync());
  }

  testWidgets('refresh button refreshes dashboard and attendance', (tester) async {
    await pumpDashboard(tester, loadedState);

    await tester.tap(find.byTooltip('Refresh dashboard'));
    await tester.pump();

    verifyRefreshedOnceWithoutAttendanceActions();
  });

  testWidgets('try again refreshes dashboard and attendance', (tester) async {
    await pumpDashboard(tester, const DashboardError(DashboardCubit.noSavedProfileMessage));

    expect(find.text(DashboardCubit.noSavedProfileMessage), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();

    verifyRefreshedOnceWithoutAttendanceActions();
  });

  testWidgets('pull-to-refresh waits for dashboard and attendance', (tester) async {
    final attendanceRefresh = Completer<void>();
    when(() => attendanceCubit.loadToday()).thenAnswer((_) => attendanceRefresh.future);

    await pumpDashboard(tester, loadedState);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The indicator stays visible until the attendance refresh completes.
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    attendanceRefresh.complete();
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
    verifyRefreshedOnceWithoutAttendanceActions();
  });

  testWidgets('cached data after a failed cold start keeps attendance and leave usable', (tester) async {
    await pumpDashboard(
      tester,
      DashboardLoaded(
        employee: employee,
        casualBalance: 5,
        sickBalance: 2,
        isFromCache: true,
        savedAt: DateTime(2026, 10, 28, 9, 30),
      ),
    );

    expect(find.text('Offline. Showing data saved on 28 Oct, 09:30 AM.'), findsOneWidget);
    expect(find.text('Alex Johnson'), findsOneWidget);

    final checkIn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Check In'));
    expect(checkIn.onPressed, isNotNull);

    // The balance sits below the Recent Attendance section, off the test screen.
    await tester.scrollUntilVisible(find.text('5 days available'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('5 days available'), findsOneWidget);

    final leaveButton = find.text('Apply for Leave / View Requests');
    await tester.scrollUntilVisible(leaveButton, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(leaveButton);
    // The mocked leave list never finishes loading, so its spinner keeps
    // animating; pump through the route transition instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LeavePage), findsOneWidget);
    expect(find.text('Available: 5 casual, 2 sick days'), findsOneWidget);
  });

  testWidgets('cached data is shown without an offline banner while refreshing', (tester) async {
    await pumpDashboard(
      tester,
      DashboardLoaded(
        employee: employee,
        casualBalance: 5,
        sickBalance: 2,
        isFromCache: true,
        savedAt: DateTime(2026, 10, 28, 9, 30),
        isRefreshing: true,
      ),
    );

    expect(find.text('Alex Johnson'), findsOneWidget);
    expect(find.textContaining('Offline.'), findsNothing);
  });

  group('recent attendance', () {
    AttendanceEvent historyEvent(String eventId, AttendanceEventType type, String companyDate, AttendanceSyncStatus status) {
      return AttendanceEvent(
        eventId: eventId,
        employeeId: 'EMP001',
        type: type,
        occurredAt: DateTime.parse('${companyDate}T04:00:00Z'),
        companyDate: companyDate,
        latitude: 11.190723,
        longitude: 75.950761,
        accuracyMeters: 10,
        status: status,
      );
    }

    Future<void> scrollToRecentAttendance(WidgetTester tester) {
      return tester.scrollUntilVisible(find.text('Recent Attendance'), 200, scrollable: find.byType(Scrollable).first);
    }

    testWidgets('lists events with their type, date and sync status', (tester) async {
      whenListen(
        attendanceCubit,
        const Stream<AttendanceState>.empty(),
        initialState: AttendanceState(
          recentEvents: [
            historyEvent('out', AttendanceEventType.checkOut, '2026-10-28', AttendanceSyncStatus.pending),
            historyEvent('in', AttendanceEventType.checkIn, '2026-10-28', AttendanceSyncStatus.synced),
            historyEvent('rejected', AttendanceEventType.checkIn, '2026-10-27', AttendanceSyncStatus.rejected),
          ],
        ),
      );
      await pumpDashboard(tester, loadedState);
      await scrollToRecentAttendance(tester);
      await tester.scrollUntilVisible(find.text('Rejected'), 100, scrollable: find.byType(Scrollable).first);

      final history = find.ancestor(of: find.text('Pending Sync'), matching: find.byType(Card));
      expect(find.descendant(of: history, matching: find.text('Check Out')), findsOneWidget);
      expect(find.descendant(of: history, matching: find.text('Check In')), findsNWidgets(2));
      expect(find.descendant(of: history, matching: find.textContaining('Wed, 28 Oct 2026 · ')), findsNWidgets(2));
      expect(find.descendant(of: history, matching: find.textContaining('Tue, 27 Oct 2026 · ')), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Pending Sync'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    });

    testWidgets('shows an empty state when there is no history', (tester) async {
      await pumpDashboard(tester, loadedState);
      await scrollToRecentAttendance(tester);
      await tester.scrollUntilVisible(find.textContaining('No attendance records yet.'), 100, scrollable: find.byType(Scrollable).first);

      expect(find.textContaining('No attendance records yet.'), findsOneWidget);
    });

    testWidgets('shows a loading message while the first history is loading', (tester) async {
      whenListen(attendanceCubit, const Stream<AttendanceState>.empty(), initialState: const AttendanceState(isLoading: true));
      await pumpDashboard(tester, loadedState);
      await scrollToRecentAttendance(tester);
      await tester.scrollUntilVisible(find.text('Loading attendance history…'), 100, scrollable: find.byType(Scrollable).first);

      expect(find.text('Loading attendance history…'), findsOneWidget);
    });
  });
}
