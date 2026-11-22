import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/db/settings_keys.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:laundry_pos/services/backup/backup_reminder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeScheduler implements ReminderScheduler {
  bool scheduled = false;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  bool throwOnSchedule = false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleWeekly() async {
    if (throwOnSchedule) throw StateError('tidak ada plugin');
    scheduleCalls++;
    scheduled = true;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    scheduled = false;
  }

  @override
  Future<bool> isScheduled() async => scheduled;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late SettingsRepository settings;
  late _FakeScheduler scheduler;
  late DateTime now;
  late BackupReminder reminder;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();
    settings = SettingsRepository(db);
    await settings.loadAll(force: true);

    now = DateTime(2026, 11, 23, 8);
    scheduler = _FakeScheduler();
    reminder = BackupReminder(settings, scheduler: scheduler, clock: () => now);

    // Pemasangan sebelas hari lalu, belum pernah backup.
    await settings.set(
      SettingsKeys.seededAt,
      now.subtract(const Duration(days: 11)).toIso8601String(),
    );
  });

  tearDown(() async => db.close());

  test('belum pernah backup dihitung dari hari pemasangan', () async {
    final status = reminder.status();

    expect(status.neverBackedUp, isTrue);
    expect(status.daysSince, 11);
    expect(status.overdue, isTrue);
  });

  test('pemasangan baru belum dianggap terlambat', () async {
    await settings.set(
      SettingsKeys.seededAt,
      now.subtract(const Duration(days: 3)).toIso8601String(),
    );

    final status = reminder.status();

    expect(status.overdue, isFalse);
    expect(status.nextDue, now.add(const Duration(days: 4)));
  });

  test('tepat tujuh hari sudah terlambat, enam hari belum', () async {
    await settings.set(
      SettingsKeys.backupLastAt,
      now.subtract(const Duration(days: 6, hours: 23)).toIso8601String(),
    );
    expect(reminder.status().overdue, isFalse);

    await settings.set(
      SettingsKeys.backupLastAt,
      now.subtract(const Duration(days: 7)).toIso8601String(),
    );
    expect(reminder.status().overdue, isTrue);
  });

  test('markDone mencatat backup dan memulai ulang hitungan seminggu',
      () async {
    await reminder.markDone(BackupMethod.share);

    final status = reminder.status();
    expect(status.neverBackedUp, isFalse);
    expect(status.method, BackupMethod.share);
    expect(status.overdue, isFalse);
    expect(status.nextDue, now.add(const Duration(days: 7)));

    // Jadwal lama dibatalkan dan jadwal baru dipasang tepat satu kali.
    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.scheduled, isTrue);
  });

  test('backup di HP juga dicatat, dengan caranya', () async {
    await reminder.markDone(BackupMethod.device);

    expect(reminder.status().method, BackupMethod.device);
  });

  test('ensureScheduled hanya memasang bila belum ada jadwal', () async {
    await reminder.ensureScheduled();
    expect(scheduler.scheduleCalls, 1);

    await reminder.ensureScheduled();
    expect(scheduler.scheduleCalls, 1);
  });

  test('kegagalan memasang notifikasi tidak menjatuhkan aplikasi', () async {
    scheduler.throwOnSchedule = true;

    await reminder.ensureScheduled();
    await reminder.markDone(BackupMethod.share);

    // Backup tetap tercatat walau notifikasinya gagal dipasang.
    expect(reminder.status().neverBackedUp, isFalse);
  });

  test('dialog pengingat muncul sekali sehari dan hanya saat terlambat',
      () async {
    expect(reminder.shouldPromptNow(), isTrue);

    await reminder.markPrompted();
    expect(reminder.shouldPromptNow(), isFalse);

    now = now.add(const Duration(days: 1));
    expect(reminder.shouldPromptNow(), isTrue);

    await reminder.markDone(BackupMethod.share);
    expect(reminder.shouldPromptNow(), isFalse);
  });

  test('BackupMethod.fromCode mengenali kode tersimpan', () {
    expect(BackupMethod.fromCode('share'), BackupMethod.share);
    expect(BackupMethod.fromCode('device'), BackupMethod.device);
    expect(BackupMethod.fromCode('lain'), isNull);
    expect(BackupMethod.fromCode(null), isNull);
  });
}
