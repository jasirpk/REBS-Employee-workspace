import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/core/time/company_clock.dart';
import 'package:frontend/features/leave/data/leave_repository.dart';
import 'package:frontend/features/leave/domain/leave_request.dart';
import 'package:frontend/features/leave/presentation/leave_cubit.dart';

class MockLeaveRepository extends Mock implements LeaveRepository {}

void main() {
  late MockLeaveRepository repository;
  late LeaveCubit cubit;

  // A start date safely after the real company date, so the policy's
  // "not before today" rule passes.
  final startDate = DateTime.parse(CompanyClock.today()).add(const Duration(days: 7)).toIso8601String().substring(0, 10);

  LeaveRequest leaveRequest(String id, {LeaveStatus status = LeaveStatus.pending}) {
    return LeaveRequest(
      id: id,
      employeeId: 'EMP001',
      type: LeaveType.casual,
      startDate: startDate,
      endDate: startDate,
      days: 1,
      reason: 'Attending a family wedding',
      status: status,
      createdAt: DateTime.utc(2026, 10, 29, 5),
    );
  }

  void stubLoad(List<LeaveRequest> requests, {bool isFromCache = false}) {
    when(() => repository.loadLeaveRequests()).thenAnswer(
      (_) async => LeaveRequestsResult(requests: requests, isFromCache: isFromCache),
    );
  }

  void stubSubmit(Future<LeaveRequest> Function() answer) {
    when(
      () => repository.submitLeaveRequest(
        type: any(named: 'type'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        reason: any(named: 'reason'),
      ),
    ).thenAnswer((_) => answer());
  }

  Future<bool> submitValidRequest() {
    return cubit.submitRequest(
      type: LeaveType.casual,
      startDate: startDate,
      endDate: startDate,
      reason: 'Attending a family wedding',
      availableDays: 8,
    );
  }

  setUpAll(() {
    registerFallbackValue(LeaveType.casual);
  });

  setUp(() {
    repository = MockLeaveRepository();
    cubit = LeaveCubit(repository: repository);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('loadRequests', () {
    test('shows requests from the server', () async {
      stubLoad([leaveRequest('LEAVE001', status: LeaveStatus.approved)]);

      await cubit.loadRequests();

      expect(cubit.state.requests.single.id, 'LEAVE001');
      expect(cubit.state.isFromCache, isFalse);
      expect(cubit.state.hasLoaded, isTrue);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.message, isNull);
    });

    test('shows cached requests after a network failure', () async {
      stubLoad([leaveRequest('LEAVE001')], isFromCache: true);

      await cubit.loadRequests();

      expect(cubit.state.requests.single.id, 'LEAVE001');
      expect(cubit.state.isFromCache, isTrue);
      expect(cubit.state.hasLoaded, isTrue);
    });

    test('reports an empty offline cache', () async {
      stubLoad([], isFromCache: true);

      await cubit.loadRequests();

      expect(cubit.state.requests, isEmpty);
      expect(cubit.state.isFromCache, isTrue);
      expect(cubit.state.hasLoaded, isTrue);
      expect(cubit.state.isLoading, isFalse);
    });
  });

  group('submitRequest', () {
    test('rejects invalid input without calling the API', () async {
      final submitted = await cubit.submitRequest(
        type: LeaveType.casual,
        startDate: startDate,
        endDate: startDate,
        reason: 'too short',
        availableDays: 8,
      );

      expect(submitted, isFalse);
      expect(cubit.state.message, 'Reason must contain at least 10 characters, not counting spaces.');
      expect(cubit.state.messageIsError, isTrue);
      verifyNever(
        () => repository.submitLeaveRequest(
          type: any(named: 'type'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          reason: any(named: 'reason'),
        ),
      );
    });

    test('rejects dates that overlap a loaded request without calling the API', () async {
      stubLoad([leaveRequest('LEAVE001')]);
      await cubit.loadRequests();

      final submitted = await submitValidRequest();

      expect(submitted, isFalse);
      expect(cubit.state.message, 'These dates overlap an existing pending or approved leave request.');
      verifyNever(
        () => repository.submitLeaveRequest(
          type: any(named: 'type'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          reason: any(named: 'reason'),
        ),
      );
    });

    test('submits a valid request and refreshes the list', () async {
      final created = leaveRequest('LEAVE002');
      stubSubmit(() async => created);
      stubLoad([created]);

      final submitted = await submitValidRequest();

      expect(submitted, isTrue);
      expect(cubit.state.message, 'Leave request submitted.');
      expect(cubit.state.messageIsError, isFalse);
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.requests.single.id, 'LEAVE002');
      verify(
        () => repository.submitLeaveRequest(
          type: LeaveType.casual,
          startDate: startDate,
          endDate: startDate,
          reason: 'Attending a family wedding',
        ),
      ).called(1);
      verify(() => repository.loadLeaveRequests()).called(1);
    });

    test('shows the server validation message', () async {
      stubSubmit(() async => throw const LeaveSubmissionException('Simulated leave validation rejection'));

      final submitted = await submitValidRequest();

      expect(submitted, isFalse);
      expect(cubit.state.message, 'Simulated leave validation rejection');
      expect(cubit.state.messageIsError, isTrue);
      expect(cubit.state.isSubmitting, isFalse);
      verifyNever(() => repository.loadLeaveRequests());
    });

    test('ignores a second submission while the first is in progress', () async {
      final response = Completer<LeaveRequest>();
      stubSubmit(() => response.future);
      stubLoad([leaveRequest('LEAVE002')]);

      final first = submitValidRequest();
      expect(cubit.state.isSubmitting, isTrue);

      final second = await submitValidRequest();
      expect(second, isFalse);

      response.complete(leaveRequest('LEAVE002'));
      expect(await first, isTrue);

      verify(
        () => repository.submitLeaveRequest(
          type: any(named: 'type'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          reason: any(named: 'reason'),
        ),
      ).called(1);
    });
  });
}
