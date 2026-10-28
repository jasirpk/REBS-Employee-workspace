import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/time/company_clock.dart';
import '../../dashboard/presentaion/dashboard_cubit.dart';
import '../../dashboard/presentaion/dashboard_state.dart';
import '../domain/leave_request.dart';
import 'leave_cubit.dart';
import 'leave_state.dart';

class LeavePage extends StatefulWidget {
  const LeavePage({super.key});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  static final DateFormat _apiDateFormat = DateFormat('yyyy-MM-dd');

  final TextEditingController _reasonController = TextEditingController();
  LeaveType _type = LeaveType.casual;
  String? _startDate;
  String? _endDate;

  @override
  void initState() {
    super.initState();
    context.read<LeaveCubit>().loadRequests();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int? _availableDays() {
    final dashboardState = context.read<DashboardCubit>().state;
    if (dashboardState is! DashboardLoaded) return null;

    return _type == LeaveType.casual ? dashboardState.casualBalance : dashboardState.sickBalance;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = DateTime.parse(CompanyClock.today());
    final selected = isStart ? _startDate : (_endDate ?? _startDate);

    final picked = await showDatePicker(
      context: context,
      initialDate: selected == null ? today : DateTime.parse(selected),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = _apiDateFormat.format(picked);
      } else {
        _endDate = _apiDateFormat.format(picked);
      }
    });
  }

  Future<void> _submit() async {
    final submitted = await context.read<LeaveCubit>().submitRequest(
      type: _type,
      startDate: _startDate,
      endDate: _endDate,
      reason: _reasonController.text,
      availableDays: _availableDays(),
    );

    if (!submitted || !mounted) return;

    setState(() {
      _startDate = null;
      _endDate = null;
      _reasonController.clear();
    });
    context.read<DashboardCubit>().loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          IconButton(
            tooltip: 'Refresh leave requests',
            onPressed: () => context.read<LeaveCubit>().loadRequests(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<LeaveCubit, LeaveState>(
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: () => context.read<LeaveCubit>().loadRequests(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildForm(context, state),
                const SizedBox(height: 20),
                Text('My Requests', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ..._buildRequests(context, state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, LeaveState state) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Apply for Leave', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const _BalanceSummary(),
            const SizedBox(height: 16),
            SegmentedButton<LeaveType>(
              segments: const [
                ButtonSegment(value: LeaveType.casual, label: Text('Casual'), icon: Icon(Icons.beach_access_outlined)),
                ButtonSegment(value: LeaveType.sick, label: Text('Sick'), icon: Icon(Icons.local_hospital_outlined)),
              ],
              selected: {_type},
              onSelectionChanged: state.isSubmitting ? null : (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'Start date',
                    date: _startDate,
                    onPressed: state.isSubmitting ? null : () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateButton(
                    label: 'End date',
                    date: _endDate,
                    onPressed: state.isSubmitting ? null : () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              enabled: !state.isSubmitting,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'At least 10 characters',
                border: OutlineInputBorder(),
              ),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 12),
              Text(
                state.message!,
                style: TextStyle(color: state.messageIsError ? theme.colorScheme.error : theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRequests(BuildContext context, LeaveState state) {
    if (!state.hasLoaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state.requests.isEmpty) {
      return [
        _InfoCard(
          icon: state.isFromCache ? Icons.cloud_off : Icons.event_available_outlined,
          message: state.isFromCache
              ? 'You are offline and no leave requests are saved on this device yet.'
              : 'You have not applied for leave yet.',
          onRetry: state.isFromCache ? () => context.read<LeaveCubit>().loadRequests() : null,
        ),
      ];
    }

    return [
      if (state.isFromCache) ...[
        _InfoCard(
          icon: Icons.cloud_off,
          message: 'Offline. Showing leave requests saved on this device. Submitting needs a connection.',
          onRetry: () => context.read<LeaveCubit>().loadRequests(),
        ),
        const SizedBox(height: 8),
      ],
      for (final request in state.requests) ...[
        _LeaveRequestCard(request: request),
        const SizedBox(height: 8),
      ],
    ];
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final text = state is DashboardLoaded
            ? 'Available: ${state.casualBalance} casual, ${state.sickBalance} sick days'
            : 'Leave balance is loading…';

        return Text(text, style: Theme.of(context).textTheme.bodyMedium);
      },
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String? date;
  final VoidCallback? onPressed;

  const _DateButton({required this.label, required this.date, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(date == null ? label : _displayDate(date!)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  const _InfoCard({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  final LeaveRequest request;

  const _LeaveRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final typeLabel = request.type == LeaveType.casual ? 'Casual leave' : 'Sick leave';
    final dayLabel = request.days == 1 ? '1 day' : '${request.days} days';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$typeLabel · $dayLabel', style: Theme.of(context).textTheme.titleSmall),
                ),
                _LeaveStatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('${_displayDate(request.startDate)} – ${_displayDate(request.endDate)}'),
            const SizedBox(height: 4),
            Text(request.reason, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LeaveStatusChip extends StatelessWidget {
  final LeaveStatus status;

  const _LeaveStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      LeaveStatus.pending => ('Pending', Colors.orange.shade800),
      LeaveStatus.approved => ('Approved', Colors.green.shade700),
      LeaveStatus.rejected => ('Rejected', Theme.of(context).colorScheme.error),
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

String _displayDate(String date) => DateFormat('d MMM yyyy').format(DateTime.parse(date));
