import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:laundry_pos/services/auth/pin_guard.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late SettingsRepository settings;
  late DateTime now;
  late PinGuard guard;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();
    settings = SettingsRepository(db);
    await settings.loadAll(force: true);

    now = DateTime(2026, 11, 23, 9);
    guard = PinGuard(settings, clock: () => now);
  });

  tearDown(() async => db.close());

  Future<Duration> gagal(int kali) async {
    var terakhir = Duration.zero;
    for (var i = 0; i < kali; i++) {
      terakhir = await guard.recordFailure();
    }
    return terakhir;
  }

  test('lima kesempatan pertama tidak mengunci', () async {
    await gagal(4);

    expect(guard.lockRemaining(), isNull);
    expect(guard.attemptsLeftInRound, 1);
  });

  test('kegagalan kelima mengunci 30 detik', () async {
    final lock = await gagal(5);

    expect(lock, const Duration(seconds: 30));
    expect(guard.lockRemaining(), const Duration(seconds: 30));
  });

  test('kunci berakhir saat waktunya lewat', () async {
    await gagal(5);

    now = now.add(const Duration(seconds: 31));

    expect(guard.lockRemaining(), isNull);
  });

  test('kunci makin lama: 30 detik, 5 menit, lalu 15 menit', () {
    expect(PinGuard.lockFor(5), const Duration(seconds: 30));
    expect(PinGuard.lockFor(10), const Duration(minutes: 5));
    expect(PinGuard.lockFor(15), const Duration(minutes: 15));
    expect(PinGuard.lockFor(40), const Duration(minutes: 15));
  });

  test('kegagalan di antara kelipatan lima tidak mengunci', () {
    for (final n in [1, 2, 3, 4, 6, 7, 8, 9, 11]) {
      expect(PinGuard.lockFor(n), Duration.zero, reason: 'gagal ke-$n');
    }
  });

  test('putaran kedua dimulai lagi dengan lima kesempatan', () async {
    await gagal(5);
    now = now.add(const Duration(minutes: 1));

    await gagal(2);

    expect(guard.lockRemaining(), isNull);
    expect(guard.attemptsLeftInRound, 3);
  });

  test('PIN benar membersihkan hitungan dan kunci', () async {
    await gagal(5);

    await guard.recordSuccess();

    expect(guard.failures, 0);
    expect(guard.lockRemaining(), isNull);
  });

  test('hitungan bertahan setelah penghitung dibuat ulang', () async {
    await gagal(5);

    // Aplikasi dibuka ulang: objek baru, pengaturan yang sama.
    final baru = PinGuard(settings, clock: () => now);

    expect(baru.lockRemaining(), isNotNull);
    expect(baru.failures, 5);
  });

  test('describe membulatkan ke atas', () {
    expect(PinGuard.describe(const Duration(seconds: 30)), '30 detik');
    expect(PinGuard.describe(const Duration(milliseconds: 400)), '1 detik');
    expect(PinGuard.describe(const Duration(seconds: 61)), '2 menit');
    expect(PinGuard.describe(const Duration(minutes: 5)), '5 menit');
  });
}
