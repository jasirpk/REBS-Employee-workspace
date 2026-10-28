
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/leave/domain/leave_policy.dart';
import 'package:frontend/features/leave/domain/leave_request.dart';

void main() {
  const policy = LeavePolicy();
  const today = '2026-10-28';

  LeaveRequest existingRequest({
    required String startDate,
    required String endDate,
    LeaveStatus status = LeaveStatus.pending,
  }) {
    return LeaveRequest(
      id: 'LEAVE-$startDate',
      employeeId: 'EMP001',
      type: LeaveType.casual,
      startDate: startDate,
      endDate: endDate,
      days: LeavePolicy.countDays(startDate, endDate),
      reason: 'Personal family commitments',
      status: status,
      createdAt: DateTime.utc(2026, 10, 10, 9),
    );
  }

  String? validate({
    LeaveType? type = LeaveType.casual,
    String? startDate = '2026-11-02',
    String? endDate = '2026-11-03',
    String reason = 'Attending a family wedding',
    int availableDays = 8,
    List<LeaveRequest> existingRequests = const [],
  }) {
    return policy.validate(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      availableDays: availableDays,
      existingRequests: existingRequests,
      today: today,
    );
  }

  test('accepts a valid request', () {
    expect(validate(), isNull);
  });

  test('requires a leave type', () {
    expect(validate(type: null), 'Please select a leave type.');
  });

  test('requires both dates', () {
    expect(validate(startDate: null), 'Please select a start date and an end date.');
    expect(validate(endDate: null), 'Please select a start date and an end date.');
  });

  test('rejects dates that are not real calendar dates', () {
    expect(validate(startDate: '2026-02-30', endDate: '2026-03-02'), 'Please select valid dates.');
    expect(validate(endDate: '2026-11-3'), 'Please select valid dates.');
  });

  test('rejects a start date before today', () {
    expect(validate(startDate: '2026-10-27', endDate: '2026-10-28'), 'Leave cannot start before today.');
  });

  test('accepts a start date of today', () {
    expect(validate(startDate: today, endDate: today), isNull);
  });

  test('rejects an end date before the start date', () {
    expect(validate(startDate: '2026-11-05', endDate: '2026-11-04'), 'End date cannot be before the start date.');
  });

  test('requires at least 10 non-whitespace characters in the reason', () {
    expect(
      validate(reason: ' a b c d e f g h i '),
      'Reason must contain at least 10 characters, not counting spaces.',
    );
    expect(validate(reason: 'a b c d e f g h i j'), isNull);
  });

  test('rejects a request longer than the available balance', () {
    expect(
      validate(startDate: '2026-11-02', endDate: '2026-11-04', availableDays: 2),
      'You requested 3 days, but only 2 days of casual leave are available.',
    );
  });

  test('accepts a request that uses the whole balance', () {
    expect(validate(startDate: '2026-11-02', endDate: '2026-11-03', availableDays: 2), isNull);
  });

  test('rejects dates overlapping a pending or approved request', () {
    const message = 'These dates overlap an existing pending or approved leave request.';

    expect(
      validate(existingRequests: [existingRequest(startDate: '2026-11-03', endDate: '2026-11-05')]),
      message,
    );
    expect(
      validate(
        existingRequests: [
          existingRequest(startDate: '2026-11-01', endDate: '2026-11-02', status: LeaveStatus.approved),
        ],
      ),
      message,
    );
  });

  test('allows dates covered only by a rejected request', () {
    expect(
      validate(
        existingRequests: [
          existingRequest(startDate: '2026-11-02', endDate: '2026-11-03', status: LeaveStatus.rejected),
        ],
      ),
      isNull,
    );
  });

  test('allows a request that ends the day before an existing request', () {
    expect(
      validate(existingRequests: [existingRequest(startDate: '2026-11-04', endDate: '2026-11-06')]),
      isNull,
    );
  });

  test('counts every calendar day, including both ends', () {
    expect(LeavePolicy.countDays('2026-10-31', '2026-11-01'), 2);
    expect(LeavePolicy.countDays('2026-11-02', '2026-11-02'), 1);
  });

  test('reads a leave request from the API response', () {
    final request = LeaveRequest.fromJson({
      'id': 'LEAVE001',
      'employeeId': 'EMP001',
      'type': 'CASUAL',
      'startDate': '2026-10-20',
      'endDate': '2026-10-21',
      'days': 2,
      'reason': 'Personal family commitments',
      'status': 'APPROVED',
      'createdAt': '2026-10-10T09:00:00.000Z',
    });

    expect(request.type, LeaveType.casual);
    expect(request.status, LeaveStatus.approved);
    expect(request.days, 2);
    expect(request.createdAt, DateTime.utc(2026, 10, 10, 9));
    expect(request.toJson()['status'], 'APPROVED');
  });
}
