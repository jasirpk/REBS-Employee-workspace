
import 'package:equatable/equatable.dart';

import '../domain/employee.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

final class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

final class DashboardLoaded extends DashboardState {
  final Employee employee;
  final int casualBalance;
  final int sickBalance;
  // True when the data came from the device cache instead of the server.
  final bool isFromCache;
  // When the cached data was saved; null for fresh server data.
  final DateTime? savedAt;
  // True while cached data is shown and a server refresh is still running.
  final bool isRefreshing;

  const DashboardLoaded({
    required this.employee,
    required this.casualBalance,
    required this.sickBalance,
    this.isFromCache = false,
    this.savedAt,
    this.isRefreshing = false,
  });

  @override
  List<Object?> get props => [employee, casualBalance, sickBalance, isFromCache, savedAt, isRefreshing];
}

final class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
