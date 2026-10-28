import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';

void main() {
  late String databasePath;
  late AppDatabase appDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // AppDatabase opens this file by name; this is the FFI test location,
    // not a device database.
    databasePath = p.join(await getDatabasesPath(), 'rebs_employee_workspace.db');
    await deleteDatabase(databasePath);
    appDatabase = AppDatabase();
  });

  tearDown(() async {
    await appDatabase.close();
    await deleteDatabase(databasePath);
  });

  test('upgrading from version 1 keeps attendance data and adds leave_requests', () async {
    final versionOne = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_events (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL UNIQUE,
            employee_id TEXT NOT NULL,
            type TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            company_date TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'PENDING',
            reject_reason TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT
          )
        ''');
      },
    );

    await versionOne.insert('attendance_events', {
      'event_id': 'pending-before-upgrade',
      'employee_id': 'EMP001',
      'type': 'CHECK_IN',
      'occurred_at': '2026-10-29T04:00:00.000Z',
      'company_date': '2026-10-29',
      'latitude': 11.190723,
      'longitude': 75.950761,
      'accuracy_meters': 10,
    });
    await versionOne.close();

    final db = await appDatabase.database;

    expect(await db.getVersion(), 3);

    final attendanceRows = await db.query('attendance_events');
    expect(attendanceRows.single['event_id'], 'pending-before-upgrade');
    expect(attendanceRows.single['status'], 'PENDING');

    expect(await tableExists(db, 'leave_requests'), isTrue);
    expect(await tableExists(db, 'dashboard_cache'), isTrue);
  });

  test('upgrading from version 2 keeps attendance and leave data and adds dashboard_cache', () async {
    final versionTwo = await openDatabase(
      databasePath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_events (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL UNIQUE,
            employee_id TEXT NOT NULL,
            type TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            company_date TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'PENDING',
            reject_reason TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE leave_requests (
            id TEXT PRIMARY KEY,
            employee_id TEXT NOT NULL,
            type TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            days INTEGER NOT NULL,
            reason TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    await versionTwo.insert('attendance_events', {
      'event_id': 'synced-before-upgrade',
      'employee_id': 'EMP001',
      'type': 'CHECK_IN',
      'occurred_at': '2026-10-29T04:00:00.000Z',
      'company_date': '2026-10-29',
      'latitude': 11.190723,
      'longitude': 75.950761,
      'accuracy_meters': 10,
      'status': 'SYNCED',
    });
    await versionTwo.insert('leave_requests', {
      'id': 'LEAVE001',
      'employee_id': 'EMP001',
      'type': 'CASUAL',
      'start_date': '2026-10-20',
      'end_date': '2026-10-21',
      'days': 2,
      'reason': 'Personal family commitments',
      'status': 'APPROVED',
      'created_at': '2026-10-10T09:00:00.000Z',
    });
    await versionTwo.close();

    final db = await appDatabase.database;

    expect(await db.getVersion(), 3);
    expect((await db.query('attendance_events')).single['status'], 'SYNCED');
    expect((await db.query('leave_requests')).single['status'], 'APPROVED');
    expect(await tableExists(db, 'dashboard_cache'), isTrue);
  });
}

Future<bool> tableExists(Database db, String name) async {
  final rows = await db.query('sqlite_master', where: 'type = ? AND name = ?', whereArgs: ['table', name]);
  return rows.isNotEmpty;
}
