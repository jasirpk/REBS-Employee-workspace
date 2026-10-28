
enum LeaveType {
  casual,
  sick,
}

enum LeaveStatus {
  pending,
  approved,
  rejected,
}

class LeaveRequest {
  final String id;
  final String employeeId;
  final LeaveType type;
  // Company dates in YYYY-MM-DD format, both inclusive.
  final String startDate;
  final String endDate;
  final int days;
  final String reason;
  final LeaveStatus status;
  final DateTime createdAt;

  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  String get typeValue => type == LeaveType.casual ? 'CASUAL' : 'SICK';

  String get statusValue {
    switch (status) {
      case LeaveStatus.pending:
        return 'PENDING';
      case LeaveStatus.approved:
        return 'APPROVED';
      case LeaveStatus.rejected:
        return 'REJECTED';
    }
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'CASUAL' => LeaveType.casual,
      'SICK' => LeaveType.sick,
      _ => throw FormatException('Unknown leave type: ${json['type']}'),
    };

    final status = switch (json['status']) {
      'PENDING' => LeaveStatus.pending,
      'APPROVED' => LeaveStatus.approved,
      'REJECTED' => LeaveStatus.rejected,
      _ => throw FormatException('Unknown leave status: ${json['status']}'),
    };

    return LeaveRequest(
      id: json['id'] as String,
      employeeId: json['employeeId'] as String,
      type: type,
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      days: (json['days'] as num).toInt(),
      reason: json['reason'] as String,
      status: status,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'type': typeValue,
      'startDate': startDate,
      'endDate': endDate,
      'days': days,
      'reason': reason,
      'status': statusValue,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}
