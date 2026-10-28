
import '../../../core/time/company_clock.dart';
import 'leave_request.dart';

class LeavePolicy {
  const LeavePolicy();

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  // Returns a message for the first rule that fails, or null when the
  // request is valid. Dates use the YYYY-MM-DD company date format.
  String? validate({
    required LeaveType? type,
    required String? startDate,
    required String? endDate,
    required String reason,
    required int availableDays,
    required List<LeaveRequest> existingRequests,
    String? today,
  }) {
    if (type == null) {
      return 'Please select a leave type.';
    }

    if (startDate == null || endDate == null) {
      return 'Please select a start date and an end date.';
    }

    if (!isValidDate(startDate) || !isValidDate(endDate)) {
      return 'Please select valid dates.';
    }

    if (startDate.compareTo(today ?? CompanyClock.today()) < 0) {
      return 'Leave cannot start before today.';
    }

    if (endDate.compareTo(startDate) < 0) {
      return 'End date cannot be before the start date.';
    }

    if (reason.replaceAll(RegExp(r'\s'), '').length < 10) {
      return 'Reason must contain at least 10 characters, not counting spaces.';
    }

    final days = countDays(startDate, endDate);

    if (days > availableDays) {
      final typeName = type == LeaveType.casual ? 'casual' : 'sick';
      return 'You requested $days days, but only $availableDays days of $typeName leave are available.';
    }

    final overlapsExisting = existingRequests.any(
      (request) => _blocksDates(request) && startDate.compareTo(request.endDate) <= 0 && endDate.compareTo(request.startDate) >= 0,
    );

    if (overlapsExisting) {
      return 'These dates overlap an existing pending or approved leave request.';
    }

    return null;
  }

  // Every calendar day counts, including weekends and holidays.
  static int countDays(String startDate, String endDate) {
    final start = DateTime.parse('${startDate}T00:00:00Z');
    final end = DateTime.parse('${endDate}T00:00:00Z');

    return end.difference(start).inDays + 1;
  }

  // DateTime.parse rolls invalid days over (2026-02-30 becomes March 2),
  // so the parsed date must format back to the same text.
  static bool isValidDate(String value) {
    if (!_datePattern.hasMatch(value)) return false;

    final date = DateTime.tryParse('${value}T00:00:00Z');

    return date != null && date.toIso8601String().substring(0, 10) == value;
  }

  bool _blocksDates(LeaveRequest request) {
    return request.status == LeaveStatus.pending || request.status == LeaveStatus.approved;
  }
}
