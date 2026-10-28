
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class DashboardLocalDataSource {
  final AppDatabase _appDatabase;

  DashboardLocalDataSource(this._appDatabase);

  Future<void> saveResponse(String key, Map<String, dynamic> json) async {
    final db = await _appDatabase.database;

    await db.insert(
      'dashboard_cache',
      {
        'key': key,
        'response_json': jsonEncode(json),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Returns null when nothing has been saved for [key].
  Future<({Map<String, dynamic> json, DateTime savedAt})?> getResponse(String key) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'dashboard_cache',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return (
      json: jsonDecode(rows.first['response_json'] as String) as Map<String, dynamic>,
      savedAt: DateTime.parse(rows.first['saved_at'] as String),
    );
  }
}
