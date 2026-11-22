import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/db/settings_keys.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();
    settings = SettingsRepository(db);
    await settings.loadAll(force: true);
  });

  tearDown(() async => db.close());

  test('salinan nota bawaan adalah 2 lembar', () {
    expect(settings.getInt(SettingsKeys.receiptCopies), 2);
  });
}
