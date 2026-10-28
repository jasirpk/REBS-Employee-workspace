
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/employee.dart';
import 'dashboard_cubit.dart';
import 'dashboard_state.dart';

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
            onPressed: () {
              context.read<DashboardCubit>().loadDashboard();
            },
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
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        context.read<DashboardCubit>().loadDashboard();
                      },
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

  const _DashboardContent({
    required this.employee,
    required this.casualBalance,
    required this.sickBalance,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<DashboardCubit>().loadDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(Icons.person, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
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
          Text(
            "Today's Attendance",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.radio_button_unchecked),
                      SizedBox(width: 8),
                      Text('Not Checked In'),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text('Check-in: --:--'),
                  Text('Check-out: --:--'),
                  SizedBox(height: 16),
                  Text(
                    'Attendance actions will be enabled after '
                        'offline validation and storage are implemented.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Leave Balance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _LeaveBalanceCard(
                  title: 'Casual Leave',
                  days: casualBalance,
                  icon: Icons.beach_access_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LeaveBalanceCard(
                  title: 'Sick Leave',
                  days: sickBalance,
                  icon: Icons.local_hospital_outlined,
                ),
              ),
            ],
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

class _LeaveBalanceCard extends StatelessWidget {
  final String title;
  final int days;
  final IconData icon;

  const _LeaveBalanceCard({
    required this.title,
    required this.days,
    required this.icon,
  });

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
            Text(
              '$days days available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
