import 'package:equatable/equatable.dart';

import '../domain/attendance_event.dart';

class AttendanceState extends Equatable {
  final List<AttendanceEvent> events;
  final bool isLoading;
  final bool isActionInProgress;
  final String? message;
  final bool messageIsError;

  const AttendanceState({
    this.events = const [],
    this.isLoading = false,
    this.isActionInProgress = false,
    this.message,
    this.messageIsError = false,
  });

  AttendanceState copyWith({
    List<AttendanceEvent>? events,
    bool? isLoading,
    bool? isActionInProgress,
    String? message,
    bool clearMessage = false,
    bool? messageIsError,
  }) {
    return AttendanceState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isActionInProgress:
      isActionInProgress ?? this.isActionInProgress,
      message: clearMessage ? null : message ?? this.message,
      messageIsError: messageIsError ?? this.messageIsError,
    );
  }

  @override
  List<Object?> get props => [
    events,
    isLoading,
    isActionInProgress,
    message,
    messageIsError,
  ];
}