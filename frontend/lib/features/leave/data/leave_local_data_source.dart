
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/leave_request.dart';

class LeaveLocalDataSource {
  final AppDatabase _appDatabase;

  LeaveLocalDataSource(this._appDatabase);

  // Replaces the cache with the latest list from the server, so requests
  // removed on the server do not linger offline.
  Future<void> replaceLeaveRequests(List<LeaveRequest> requests) async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      await txn.delete('leave_requests');

      for (final request in requests) {
        await txn.insert('leave_requests', _toRow(request));
      }
    });
  }

  Future<void> saveLeaveRequest(LeaveRequest request) async {
    final db = await _appDatabase.database;

    await db.insert(
      'leave_requests',
      _toRow(request),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Newest first, matching the server's order.
  Future<List<LeaveRequest>> getLeaveRequests() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'leave_requests',
      orderBy: 'created_at DESC',
    );

    return rows.map(_fromRow).toList();
  }

  Map<String, Object?> _toRow(LeaveRequest request) {
    return {
      'id': request.id,
      'employee_id': request.employeeId,
      'type': request.typeValue,
      'start_date': request.startDate,
      'end_date': request.endDate,
      'days': request.days,
      'reason': request.reason,
      'status': request.statusValue,
      'created_at': request.createdAt.toUtc().toIso8601String(),
    };
  }

  LeaveRequest _fromRow(Map<String, Object?> row) {
    return LeaveRequest.fromJson({
      'id': row['id'],
      'employeeId': row['employee_id'],
      'type': row['type'],
      'startDate': row['start_date'],
      'endDate': row['end_date'],
      'days': row['days'],
      'reason': row['reason'],
      'status': row['status'],
      'createdAt': row['created_at'],
    });
  }
}
