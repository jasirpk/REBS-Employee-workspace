
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  static const String noSavedProfileMessage =
      'No saved employee profile is available yet. Connect to the internet once to download your profile '
      'and office location. After that, you can use attendance offline.';

  final DashboardRepository _repository;

  DashboardCubit(this._repository) : super(const DashboardInitial());


  // Shows cached data straight away when there is any, then refreshes from
  // the server. A failed refresh falls back to the cache instead of an error.
  Future<void> loadDashboard() async {
    final cached = await _loadCachedDashboard(isRefreshing: true);
    emit(cached ?? const DashboardLoading());

    try {
      // Wait for both requests together so neither error goes unhandled.
      final (employee, balance) = await (
        _repository.fetchEmployee(),
        _repository.fetchLeaveBalance(),
      ).wait;

      emit(
        DashboardLoaded(
          employee: employee,
          casualBalance: (balance['casual'] as num).toInt(),
          sickBalance: (balance['sick'] as num).toInt(),
        ),
      );
    } catch (error) {
      // DIAGNOSTIC LOGGING: remove once the release network issue is verified.
      debugPrint('[diagnostic] Dashboard load failed: $error');

      // Read the cache again: one of the requests may have just updated it.
      final latestCache = await _loadCachedDashboard(isRefreshing: false);

      // With a cache the dashboard stays usable offline. Without one there is
      // no employee profile or office location yet, so attendance cannot run.
      emit(latestCache ?? const DashboardError(noSavedProfileMessage));
    }
  }

  Future<DashboardLoaded?> _loadCachedDashboard({required bool isRefreshing}) async {
    try {
      final cached = await _repository.getCachedDashboard();
      if (cached == null) return null;

      return DashboardLoaded(
        employee: cached.employee,
        casualBalance: (cached.leaveBalance['casual'] as num).toInt(),
        sickBalance: (cached.leaveBalance['sick'] as num).toInt(),
        isFromCache: true,
        savedAt: cached.savedAt,
        isRefreshing: isRefreshing,
      );
    } catch (_) {
      // An unreadable cache is treated the same as no cache.
      return null;
    }
  }
}
