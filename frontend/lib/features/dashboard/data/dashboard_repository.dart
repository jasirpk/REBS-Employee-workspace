
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/employee.dart';

class DashboardRepository {
  final Dio _dio;

  DashboardRepository(ApiClient apiClient) : _dio = apiClient.dio;

  Future<Employee> fetchEmployee() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'employee/me',
    );

    final data = response.data;

    if (data == null) {
      throw const FormatException('Employee response was empty.');
    }

    return Employee.fromJson(data);
  }

  Future<Map<String, dynamic>> fetchLeaveBalance() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'leave/balance',
    );

    final data = response.data;

    if (data == null) {
      throw const FormatException('Leave balance response was empty.');
    }

    return data;
  }
}
