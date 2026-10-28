
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/api_client.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/dashboard/presentaion/dashboard_cubit.dart';
import 'features/dashboard/presentaion/dashboard_page.dart';

void main() {
  final apiClient = ApiClient();
  final dashboardRepository = DashboardRepository(apiClient);

  runApp(
    EmployeeWorkspaceApp(
      dashboardRepository: dashboardRepository,
    ),
  );
}

class EmployeeWorkspaceApp extends StatelessWidget {
  final DashboardRepository dashboardRepository;

  const EmployeeWorkspaceApp({
    required this.dashboardRepository,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REBS Employee Workspace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3157A4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: BlocProvider(
        create: (_) => DashboardCubit(dashboardRepository)
          ..loadDashboard(),
        child: const DashboardPage(),
      ),
    );
  }
}
