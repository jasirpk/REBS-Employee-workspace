
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const String _databaseName = 'rebs_employee_workspace.db';
  static const int _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, _databaseName);

    _database = await openDatabase(
      path,
      version: _databaseVersion,
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

        // Preserve at most one non-rejected event of each type per day.
        await db.execute('''
          CREATE UNIQUE INDEX unique_active_daily_attendance
          ON attendance_events (employee_id, company_date, type)
          WHERE status != 'REJECTED'
        ''');
      },
    );

    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
