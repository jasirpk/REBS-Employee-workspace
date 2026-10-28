
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/employee.dart';
import 'dashboard_local_data_source.dart';

class CachedDashboard {
  final Employee employee;
  final Map<String, dynamic> leaveBalance;
  // When the older of the two cached responses was saved.
  final DateTime savedAt;

  const CachedDashboard({required this.employee, required this.leaveBalance, required this.savedAt});
}

class DashboardRepository {
  static const String _employeeKey = 'employee';
  static const String _leaveBalanceKey = 'leave_balance';

  final Dio _dio;
  final DashboardLocalDataSource _localDataSource;

  DashboardRepository(ApiClient apiClient, this._localDataSource) : _dio = apiClient.dio;

  Future<Employee> fetchEmployee() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'employee/me',
    );

    final data = response.data;

    if (data == null) {
      throw const FormatException('Employee response was empty.');
    }

    // Parse before caching so a malformed response never replaces good data.
    final employee = Employee.fromJson(data);
    await _localDataSource.saveResponse(_employeeKey, data);

    return employee;
  }

  Future<Map<String, dynamic>> fetchLeaveBalance() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'leave/balance',
    );

    final data = response.data;

    if (data == null) {
      throw const FormatException('Leave balance response was empty.');
    }

    if (data['casual'] is! num || data['sick'] is! num) {
      throw const FormatException('Leave balance response was malformed.');
    }

    await _localDataSource.saveResponse(_leaveBalanceKey, data);

    return data;
  }

  // Returns null unless both the employee and the balance have been cached.
  Future<CachedDashboard?> getCachedDashboard() async {
    final employee = await _localDataSource.getResponse(_employeeKey);
    final leaveBalance = await _localDataSource.getResponse(_leaveBalanceKey);

    if (employee == null || leaveBalance == null) return null;

    return CachedDashboard(
      employee: Employee.fromJson(employee.json),
      leaveBalance: leaveBalance.json,
      savedAt: employee.savedAt.isBefore(leaveBalance.savedAt) ? employee.savedAt : leaveBalance.savedAt,
    );
  }
}
