
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/config/api_config.dart';
import 'core/config/configuration_error_app.dart';
import 'core/database/app_database.dart';
import 'features/attendance/data/attendance_local_data_source.dart';
import 'features/attendance/data/attendance_sync_coordinator.dart';
import 'features/attendance/data/device_location_service.dart';
import 'features/attendance/domain/attendance_service.dart';
import 'features/attendance/presentation/attendance_cubit.dart';
import 'core/network/api_client.dart';
import 'features/dashboard/data/dashboard_local_data_source.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/dashboard/presentaion/dashboard_cubit.dart';
import 'features/dashboard/presentaion/dashboard_page.dart';
import 'features/leave/data/leave_local_data_source.dart';
import 'features/leave/data/leave_repository.dart';
import 'features/leave/presentation/leave_cubit.dart';

void main() async{
  // frontend/.env is bundled as an asset (pubspec.yaml) and read here, before
  // the API client is created. If it is empty or unreadable, API_BASE_URL is
  // empty and the configuration error screen explains the fix, instead of the
  // app crashing at start-up.
  try {
    await dotenv.load(fileName: ".env");
  } catch (error) {
    debugPrint('Could not load .env: $error');
  }

  final apiConfigError = ApiConfig.validateBaseUrl(ApiConfig.baseUrl);
  if (apiConfigError != null) {
    runApp(ConfigurationErrorApp(message: apiConfigError));
    return;
  }

  final apiClient = ApiClient();
  final appDatabase = AppDatabase();
  final attendanceLocalDataSource = AttendanceLocalDataSource(appDatabase);

  final attendanceService = AttendanceService(
    localDataSource: attendanceLocalDataSource,
    locationService: DeviceLocationService(),
  );

  final syncCoordinator = AttendanceSyncCoordinator(
    localDataSource: attendanceLocalDataSource,
    apiClient: apiClient,
  );

  final attendanceCubit = AttendanceCubit(
    localDataSource: attendanceLocalDataSource,
    attendanceService: attendanceService,
    syncCoordinator: syncCoordinator,
    connectivityChanges: Connectivity().onConnectivityChanged,
  );
  final dashboardRepository = DashboardRepository(apiClient, DashboardLocalDataSource(appDatabase));

  final leaveCubit = LeaveCubit(
    repository: LeaveRepository(
      apiClient: apiClient,
      localDataSource: LeaveLocalDataSource(appDatabase),
    ),
  );

  runApp(
    EmployeeWorkspaceApp(
      dashboardRepository: dashboardRepository,
      attendanceCubit: attendanceCubit,
      leaveCubit: leaveCubit,
    ),
  );

  attendanceCubit.startAutoSync();
}

class EmployeeWorkspaceApp extends StatelessWidget {
  final DashboardRepository dashboardRepository;
  final AttendanceCubit attendanceCubit;
  final LeaveCubit leaveCubit;

  const EmployeeWorkspaceApp({
    required this.dashboardRepository,
    required this.attendanceCubit,
    required this.leaveCubit,
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
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => DashboardCubit(dashboardRepository)
              ..loadDashboard(),
          ),
          BlocProvider.value(
            value: attendanceCubit,
          ),
          BlocProvider.value(value: leaveCubit),
        ],
        child: const DashboardPage(),
      ),
    );
  }
}
