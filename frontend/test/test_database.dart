import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';

Future<AppDatabase> createTestDatabase() async {
  sqfliteFfiInit();

  final testDb = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_events (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL UNIQUE,
            employee_id TEXT NOT NULL,
            type TEXT NOT NULL
              CHECK (type IN ('CHECK_IN', 'CHECK_OUT')),
            occurred_at TEXT NOT NULL,
            company_date TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'PENDING'
              CHECK (status IN ('PENDING', 'SYNCED', 'REJECTED')),
            reject_reason TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT
          )
        ''');

        await db.execute('''
          CREATE UNIQUE INDEX unique_active_daily_attendance
          ON attendance_events (employee_id, company_date, type)
          WHERE status != 'REJECTED'
        ''');
      },
    ),
  );

  return AppDatabase(databaseOpener: () async => testDb);
}