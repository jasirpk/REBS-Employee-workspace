import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/time/company_clock.dart';
import '../../attendance/domain/attendance_event.dart';
import '../../attendance/domain/office_location.dart';
import '../../attendance/presentation/attendance_cubit.dart';
import '../../attendance/presentation/attendance_state.dart';
import '../../attendance/presentation/worked_duration_text.dart';
import '../../leave/presentation/leave_cubit.dart';
import '../../leave/presentation/leave_page.dart';
import '../domain/employee.dart';
import 'dashboard_cubit.dart';
import 'dashboard_state.dart';

// Shared by every user-triggered refresh. Both cubits report their own
// failures through state, so this only waits for them to finish.
Future<void> _refreshDashboardAndAttendance(BuildContext context) {
  return Future.wait([
    context.read<DashboardCubit>().loadDashboard(),
    context.read<AttendanceCubit>().loadToday(),
  ]);
}

// Pushed routes sit beside the home route, so pass the cubits through.
void _openLeavePage(BuildContext context) {
  final leaveCubit = context.read<LeaveCubit>();
  final dashboardCubit = context.read<DashboardCubit>();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: leaveCubit),
          BlocProvider.value(value: dashboardCubit),
        ],
        child: const LeavePage(),
      ),
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Workspace'),
        actions: [
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: () => _refreshDashboardAndAttendance(context),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          if (state is DashboardInitial || state is DashboardLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is DashboardError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48),
                    const SizedBox(height: 12),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _refreshDashboardAndAttendance(context),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is DashboardLoaded) {
            return _DashboardContent(
              employee: state.employee,
              casualBalance: state.casualBalance,
              sickBalance: state.sickBalance,
              // Only once the refresh has failed; while it runs the cached data is
              // simply shown.
              offlineSavedAt: state.isFromCache && !state.isRefreshing ? state.savedAt : null,
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final Employee employee;
  final int casualBalance;
  final int sickBalance;
  // Set when the server could not be reached and cached data is shown.
  final DateTime? offlineSavedAt;

  const _DashboardContent({required this.employee, required this.casualBalance, required this.sickBalance, this.offlineSavedAt});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refreshDashboardAndAttendance(context),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (offlineSavedAt != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Offline. Showing data saved on ${CompanyClock.format(offlineSavedAt!, 'd MMM, hh:mm a')}.'),
                    ),
                    TextButton(
                      onPressed: () => _refreshDashboardAndAttendance(context),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 30)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee.name, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text('Employee ID: ${employee.id}'),
                        Text(employee.department),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("Today's Attendance", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _AttendanceCard(employee: employee),
          const SizedBox(height: 20),
          Text('Recent Attendance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const _RecentAttendance(),
          const SizedBox(height: 20),
          Text('Leave Balance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _LeaveBalanceCard(title: 'Casual Leave', days: casualBalance, icon: Icons.beach_access_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LeaveBalanceCard(title: 'Sick Leave', days: sickBalance, icon: Icons.local_hospital_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openLeavePage(context),
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('Apply for Leave / View Requests'),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Office location policy'),
              subtitle: Text(
                'Attendance is allowed within '
                '${employee.officeRadiusMeters} metres of the office.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final Employee employee;

  const _AttendanceCard({required this.employee});

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return CompanyClock.format(time, 'hh:mm a');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AttendanceCubit, AttendanceState>(
      builder: (context, state) {
        final activeEvents = state.events.where((event) => event.status != AttendanceSyncStatus.rejected).toList()
          ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

        final checkIns = activeEvents.where((event) => event.type == AttendanceEventType.checkIn).toList();

        final checkOuts = activeEvents.where((event) => event.type == AttendanceEventType.checkOut).toList();

        final hasCheckedIn = checkIns.isNotEmpty;
        final hasCheckedOut = checkOuts.isNotEmpty;
        final canCheckIn = !hasCheckedIn;
        final canCheckOut = hasCheckedIn && !hasCheckedOut;

        final office = OfficeLocation(
          latitude: employee.officeLatitude,
          longitude: employee.officeLongitude,
          radiusMeters: employee.officeRadiusMeters.toDouble(),
        );

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasCheckedOut
                          ? Icons.check_circle
                          : hasCheckedIn
                          ? Icons.work_history_outlined
                          : Icons.radio_button_unchecked,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasCheckedOut
                            ? 'Checked Out'
                            : hasCheckedIn
                            ? 'Checked In'
                            : 'Not Checked In',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (state.isLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Check-in: ${_formatTime(checkIns.firstOrNull?.occurredAt)}'),
                Text('Check-out: ${_formatTime(checkOuts.firstOrNull?.occurredAt)}'),
                WorkedDurationText(checkIn: checkIns.firstOrNull?.occurredAt, checkOut: checkOuts.firstOrNull?.occurredAt),
                const SizedBox(height: 16),
                if (state.message != null) ...[
                  Text(
                    state.message!,
                    style: TextStyle(color: state.messageIsError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                ],
                if (state.events.any((event) => event.status == AttendanceSyncStatus.pending)) ...[
                  const Row(
                    children: [Icon(Icons.cloud_upload_outlined, size: 18), SizedBox(width: 6), Text('Some attendance events are waiting to sync.')],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.isActionInProgress ? null : () => context.read<AttendanceCubit>().retrySync(),
                      child: const Text('Sync Now'),
                    ),
                  ),
                ],
                if (state.events.any((event) => event.status == AttendanceSyncStatus.rejected))
                  ...state.events
                      .where((event) => event.status == AttendanceSyncStatus.rejected)
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${event.typeValue}: ${event.rejectReason ?? 'Rejected by server.'}',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: canCheckIn && !state.isActionInProgress && !state.isLoading
                            ? () => context.read<AttendanceCubit>().recordAttendance(
                                employeeId: employee.id,
                                type: AttendanceEventType.checkIn,
                                office: office,
                              )
                            : null,
                        child: const Text('Check In'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: canCheckOut && !state.isActionInProgress && !state.isLoading
                            ? () => context.read<AttendanceCubit>().recordAttendance(
                                employeeId: employee.id,
                                type: AttendanceEventType.checkOut,
                                office: office,
                              )
                            : null,
                        child: const Text('Check Out'),
                      ),
                    ),
                  ],
                ),
                if (state.isActionInProgress) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  const Text('Processing attendance…'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// The latest attendance events across all dates, read from SQLite so they
// stay visible offline.
class _RecentAttendance extends StatelessWidget {
  const _RecentAttendance();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AttendanceCubit, AttendanceState>(
      builder: (context, state) {
        if (state.recentEvents.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.isLoading
                          ? 'Loading attendance history…'
                          : 'No attendance records yet. Your check-ins and check-outs will appear here.',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              for (final event in state.recentEvents) _RecentAttendanceRow(event: event),
            ],
          ),
        );
      },
    );
  }
}

class _RecentAttendanceRow extends StatelessWidget {
  final AttendanceEvent event;

  const _RecentAttendanceRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final isCheckIn = event.type == AttendanceEventType.checkIn;
    final date = DateFormat('EEE, d MMM yyyy').format(DateTime.parse(event.companyDate));
    final time = CompanyClock.format(event.occurredAt, 'hh:mm a');

    return ListTile(
      leading: Icon(isCheckIn ? Icons.login : Icons.logout),
      title: Text(isCheckIn ? 'Check In' : 'Check Out'),
      subtitle: Text('$date · $time'),
      trailing: _SyncStatusLabel(status: event.status),
    );
  }
}

class _SyncStatusLabel extends StatelessWidget {
  final AttendanceSyncStatus status;

  const _SyncStatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AttendanceSyncStatus.synced => ('Synced', Colors.green.shade700),
      AttendanceSyncStatus.pending => ('Pending Sync', Colors.orange.shade800),
      AttendanceSyncStatus.rejected => ('Rejected', Theme.of(context).colorScheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  final String title;
  final int days;
  final IconData icon;

  const _LeaveBalanceCard({required this.title, required this.days, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 12),
            Text(title),
            const SizedBox(height: 4),
            Text('$days days available', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
