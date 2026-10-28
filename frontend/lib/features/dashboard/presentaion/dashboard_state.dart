
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

  const DashboardLoaded({
    required this.employee,
    required this.casualBalance,
    required this.sickBalance,
  });

  @override
  List<Object?> get props => [employee, casualBalance, sickBalance];
}

final class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
