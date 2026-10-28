import 'package:equatable/equatable.dart';

import '../domain/leave_request.dart';

class LeaveState extends Equatable {
  final List<LeaveRequest> requests;
  final bool isLoading;
  // False until the first load finishes, so the page can tell an empty
  // list apart from one that has not loaded yet.
  final bool hasLoaded;
  final bool isFromCache;
  final bool isSubmitting;
  final String? message;
  final bool messageIsError;

  const LeaveState({
    this.requests = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.isFromCache = false,
    this.isSubmitting = false,
    this.message,
    this.messageIsError = false,
  });

  LeaveState copyWith({
    List<LeaveRequest>? requests,
    bool? isLoading,
    bool? hasLoaded,
    bool? isFromCache,
    bool? isSubmitting,
    String? message,
    bool clearMessage = false,
    bool? messageIsError,
  }) {
    return LeaveState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isFromCache: isFromCache ?? this.isFromCache,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      message: clearMessage ? null : message ?? this.message,
      messageIsError: messageIsError ?? this.messageIsError,
    );
  }

  @override
  List<Object?> get props => [
    requests,
    isLoading,
    hasLoaded,
    isFromCache,
    isSubmitting,
    message,
    messageIsError,
  ];
}
