
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({Future<Database> Function()? databaseOpener})
      : _databaseOpener = databaseOpener;

  final Future<Database> Function()? _databaseOpener;

  static const String _databaseName = 'rebs_employee_workspace.db';
  // Version 2 adds the leave_requests cache table.
  // Version 3 adds the dashboard_cache table.
  static const int _databaseVersion = 3;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final opener = _databaseOpener;

    if (opener != null) {
      _database = await opener();
      return _database!;
    }

    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, _databaseName);

    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Only add new tables; existing attendance data is left untouched.
        if (oldVersion < 2) {
          await _createLeaveRequestsTable(db);
        }
        if (oldVersion < 3) {
          await _createDashboardCacheTable(db);
        }
      },
    );

    return _database!;
  }

  // Public so tests can build the same schema in an in-memory database.
  static Future<void> createTables(Database db) async {
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

    await _createLeaveRequestsTable(db);
    await _createDashboardCacheTable(db);
  }

  // Raw JSON of the last successful dashboard responses, by key.
  static Future<void> _createDashboardCacheTable(Database db) async {
    await db.execute('''
    CREATE TABLE dashboard_cache (
      key TEXT PRIMARY KEY,
      response_json TEXT NOT NULL,
      saved_at TEXT NOT NULL
    )
  ''');
  }

  static Future<void> _createLeaveRequestsTable(Database db) async {
    await db.execute('''
    CREATE TABLE leave_requests (
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      type TEXT NOT NULL
        CHECK (type IN ('CASUAL', 'SICK')),
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      days INTEGER NOT NULL,
      reason TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
      created_at TEXT NOT NULL
    )
  ''');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
