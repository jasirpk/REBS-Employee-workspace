import 'package:equatable/equatable.dart';

import '../domain/attendance_event.dart';

class AttendanceState extends Equatable {
  final List<AttendanceEvent> events;
  // The latest events across all dates, newest first, for the dashboard history.
  final List<AttendanceEvent> recentEvents;
  final bool isLoading;
  final bool isActionInProgress;
  final String? message;
  final bool messageIsError;

  const AttendanceState({
    this.events = const [],
    this.recentEvents = const [],
    this.isLoading = false,
    this.isActionInProgress = false,
    this.message,
    this.messageIsError = false,
  });

  AttendanceState copyWith({
    List<AttendanceEvent>? events,
    List<AttendanceEvent>? recentEvents,
    bool? isLoading,
    bool? isActionInProgress,
    String? message,
    bool clearMessage = false,
    bool? messageIsError,
  }) {
    return AttendanceState(
      events: events ?? this.events,
      recentEvents: recentEvents ?? this.recentEvents,
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
    recentEvents,
    isLoading,
    isActionInProgress,
    message,
    messageIsError,
  ];
}