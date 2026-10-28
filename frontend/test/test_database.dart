import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/app_database.dart';

Future<AppDatabase> createTestDatabase() async {
  sqfliteFfiInit();

  final testDb = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        // Use the production schema so tests cannot drift from it.
        await AppDatabase.createTables(db);
      },
    ),
  );

  return AppDatabase(databaseOpener: () async => testDb);
}
