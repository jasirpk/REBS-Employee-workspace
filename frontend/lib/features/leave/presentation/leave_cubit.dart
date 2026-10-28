import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/leave_repository.dart';
import '../domain/leave_policy.dart';
import '../domain/leave_request.dart';
import 'leave_state.dart';

class LeaveCubit extends Cubit<LeaveState> {
  final LeaveRepository _repository;
  final LeavePolicy _policy;

  LeaveCubit({required LeaveRepository repository, LeavePolicy policy = const LeavePolicy()})
    : _repository = repository,
      _policy = policy,
      super(const LeaveState());

  Future<void> loadRequests() async {
    if (state.isLoading) return;

    emit(state.copyWith(isLoading: true, clearMessage: true));
    await _refreshRequests();
  }

  // Returns true when the request was accepted, so the page can clear its form.
  // [availableDays] is the balance for [type], or null if it is unknown.
  Future<bool> submitRequest({
    required LeaveType? type,
    required String? startDate,
    required String? endDate,
    required String reason,
    required int? availableDays,
  }) async {
    if (state.isSubmitting) return false;

    if (type != null && availableDays == null) {
      emit(state.copyWith(message: 'Leave balance is not available. Refresh and try again.', messageIsError: true));
      return false;
    }

    final validationMessage = _policy.validate(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      // Only null when no type is selected, which the policy reports first.
      availableDays: availableDays ?? 0,
      existingRequests: state.requests,
    );

    if (validationMessage != null) {
      emit(state.copyWith(message: validationMessage, messageIsError: true));
      return false;
    }

    emit(state.copyWith(isSubmitting: true, clearMessage: true));

    try {
      await _repository.submitLeaveRequest(type: type!, startDate: startDate!, endDate: endDate!, reason: reason.trim());
    } on LeaveSubmissionException catch (error) {
      // Never resubmit automatically: after a timeout the server may already
      // have saved the request.
      emit(state.copyWith(isSubmitting: false, message: error.message, messageIsError: true));
      return false;
    }

    emit(state.copyWith(isSubmitting: false, message: 'Leave request submitted.', messageIsError: false));
    await _refreshRequests();
    return true;
  }

  Future<void> _refreshRequests() async {
    try {
      final result = await _repository.loadLeaveRequests();

      emit(state.copyWith(requests: result.requests, isFromCache: result.isFromCache, isLoading: false, hasLoaded: true));
    } catch (_) {
      emit(state.copyWith(isLoading: false, hasLoaded: true, message: 'Could not load leave requests.', messageIsError: true));
    }
  }
}
