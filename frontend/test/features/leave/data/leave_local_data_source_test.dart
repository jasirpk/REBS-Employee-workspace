import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/app_database.dart';
import 'package:frontend/features/leave/data/leave_local_data_source.dart';
import 'package:frontend/features/leave/domain/leave_request.dart';

import '../../../test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late LeaveLocalDataSource localDataSource;

  setUp(() async {
    appDatabase = await createTestDatabase();
    localDataSource = LeaveLocalDataSource(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  LeaveRequest leaveRequest(String id, {LeaveStatus status = LeaveStatus.pending, DateTime? createdAt}) {
    return LeaveRequest(
      id: id,
      employeeId: 'EMP001',
      type: LeaveType.sick,
      startDate: '2026-11-02',
      endDate: '2026-11-03',
      days: 2,
      reason: 'Medical appointment and recovery',
      status: status,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 28, 9),
    );
  }

  test('stores requests with their statuses and dates, newest first', () async {
    await localDataSource.replaceLeaveRequests([
      leaveRequest('LEAVE001', status: LeaveStatus.approved, createdAt: DateTime.utc(2026, 10, 10, 9)),
      leaveRequest('LEAVE002', status: LeaveStatus.rejected, createdAt: DateTime.utc(2026, 10, 20, 9)),
    ]);

    final requests = await localDataSource.getLeaveRequests();

    expect(requests.map((request) => request.id), ['LEAVE002', 'LEAVE001']);
    expect(requests[0].status, LeaveStatus.rejected);
    expect(requests[1].status, LeaveStatus.approved);
    expect(requests[1].type, LeaveType.sick);
    expect(requests[1].startDate, '2026-11-02');
    expect(requests[1].endDate, '2026-11-03');
    expect(requests[1].days, 2);
    expect(requests[1].createdAt, DateTime.utc(2026, 10, 10, 9));
  });

  test('replacing the cache removes requests that are no longer returned', () async {
    await localDataSource.replaceLeaveRequests([leaveRequest('LEAVE001'), leaveRequest('LEAVE002')]);
    await localDataSource.replaceLeaveRequests([leaveRequest('LEAVE002', status: LeaveStatus.approved)]);

    final requests = await localDataSource.getLeaveRequests();

    expect(requests.single.id, 'LEAVE002');
    expect(requests.single.status, LeaveStatus.approved);
  });

  test('saving a request adds it or updates the cached copy', () async {
    await localDataSource.saveLeaveRequest(leaveRequest('LEAVE001'));
    await localDataSource.saveLeaveRequest(leaveRequest('LEAVE001', status: LeaveStatus.approved));

    final requests = await localDataSource.getLeaveRequests();

    expect(requests.single.status, LeaveStatus.approved);
  });
}
