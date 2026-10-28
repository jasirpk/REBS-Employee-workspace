
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  final DashboardRepository _repository;

  DashboardCubit(this._repository) : super(const DashboardInitial());


  Future<void> loadDashboard() async {
    emit(const DashboardLoading());

    try {
      final employeeFuture = _repository.fetchEmployee();
      final balanceFuture = _repository.fetchLeaveBalance();

      final employee = await employeeFuture;
      final balance = await balanceFuture;

      emit(
        DashboardLoaded(
          employee: employee,
          casualBalance: (balance['casual'] as num).toInt(),
          sickBalance: (balance['sick'] as num).toInt(),
        ),
      );
    } catch (_) {
      emit(
        const DashboardError(
          'Could not load dashboard. Check your connection and try again.',
        ),
      );
    }
  }
}
