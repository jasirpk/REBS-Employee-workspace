
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/leave_request.dart';
import 'leave_local_data_source.dart';

class LeaveRequestsResult {
  final List<LeaveRequest> requests;
  // True when the server could not be reached and the list came from the
  // last successful download.
  final bool isFromCache;

  const LeaveRequestsResult({required this.requests, required this.isFromCache});
}

class LeaveSubmissionException implements Exception {
  final String message;

  const LeaveSubmissionException(this.message);

  @override
  String toString() => message;
}

class LeaveRepository {
  final Dio _dio;
  final LeaveLocalDataSource _localDataSource;

  LeaveRepository({required ApiClient apiClient, required LeaveLocalDataSource localDataSource})
    : _dio = apiClient.dio,
      _localDataSource = localDataSource;

  // Loads requests from the server and caches them. If the server cannot be
  // reached or returns bad data, the last cached list is returned instead.
  Future<LeaveRequestsResult> loadLeaveRequests() async {
    try {
      final requests = await _fetchLeaveRequests();
      await _localDataSource.replaceLeaveRequests(requests);

      return LeaveRequestsResult(requests: requests, isFromCache: false);
    } on DioException {
      return LeaveRequestsResult(requests: await _localDataSource.getLeaveRequests(), isFromCache: true);
    } on FormatException {
      return LeaveRequestsResult(requests: await _localDataSource.getLeaveRequests(), isFromCache: true);
    }
  }

  Future<LeaveRequest> submitLeaveRequest({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'leave/requests',
        data: {
          'type': type == LeaveType.casual ? 'CASUAL' : 'SICK',
          'startDate': startDate,
          'endDate': endDate,
          'reason': reason,
        },
      );

      final data = response.data;

      if (data == null) {
        throw const FormatException('Leave request response was empty.');
      }

      final request = LeaveRequest.fromJson(data);
      await _localDataSource.saveLeaveRequest(request);

      return request;
    } on DioException catch (error) {
      throw LeaveSubmissionException(_submissionErrorMessage(error));
    } on FormatException {
      throw const LeaveSubmissionException('The leave request was sent, but the response could not be read. Refresh your leave requests.');
    }
  }

  Future<List<LeaveRequest>> _fetchLeaveRequests() async {
    final response = await _dio.get<Map<String, dynamic>>('leave/requests');

    final requests = response.data?['requests'];

    if (requests is! List) {
      throw const FormatException('Leave requests response was malformed.');
    }

    return requests.map((json) {
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Leave request must be an object.');
      }
      return LeaveRequest.fromJson(json);
    }).toList();
  }

  String _submissionErrorMessage(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;

    // Validation errors: show the server's own explanation.
    if ((statusCode == 400 || statusCode == 422) && data is Map && data['message'] is String) {
      return data['message'] as String;
    }

    switch (error.type) {
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Leave requests need an internet connection.';
      case DioExceptionType.connectionTimeout:
        return 'Could not reach the server. Please try again.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        // The server may still have saved the request.
        return 'The server took too long to respond. Refresh your leave requests before trying again.';
      default:
        return 'Could not submit the leave request. Please try again.';
    }
  }
}
