import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

/// Cara pemilik mengamankan backup.
enum BackupMethod {
  /// Dibagikan ke luar HP: WhatsApp pribadi, email, Google Drive.
  /// Satu-satunya cara yang selamat bila HP hilang atau rusak.
  share,

  /// Disimpan di HP ini, di folder backup pilihan pemilik. Berguna untuk
  /// salah-hapus. Di Download atau Documents tetap ada walau aplikasi
  /// dicopot, tapi tetap ikut hilang bersama HP.
  device;

  String get code => name;

  static BackupMethod? fromCode(String? code) {
    for (final m in values) {
      if (m.name == code) return m;
    }
    return null;
  }
}

/// Keadaan backup buatan pemilik, dihitung dari satu titik waktu.
class BackupStatus {
  const BackupStatus({
    required this.lastAt,
    required this.method,
    required this.baseline,
    required this.now,
  });

  /// Backup terakhir buatan pemilik. Null bila belum pernah.
  final DateTime? lastAt;
  final BackupMethod? method;

  /// Titik hitung mundur: backup terakhir, atau saat aplikasi dipasang bila
  /// belum pernah backup. Tanpa ini, pemasangan baru langsung dianggap
  /// terlambat berbulan-bulan.
  final DateTime baseline;
  final DateTime now;

  bool get neverBackedUp => lastAt == null;

  /// Hari penuh sejak [baseline]. Dihitung dari selisih waktu, bukan dari
  /// pergantian tanggal, supaya "7 hari" berarti 7 kali 24 jam.
  int get daysSince {
    final diff = now.difference(baseline);
    return diff.isNegative ? 0 : diff.inDays;
  }

  /// Sudah waktunya backup lagi.
  bool get overdue => !now.isBefore(nextDue);

  /// Batas berikutnya. Notifikasi mingguan dijadwalkan ke titik ini.
  DateTime get nextDue =>
      baseline.add(const Duration(days: BackupReminder.intervalDays));
}

/// Pelaksana notifikasi. Dipisah dari aturan di [BackupReminder] supaya
/// aturannya bisa diuji tanpa perangkat Android.
abstract class ReminderScheduler {
  Future<void> init();

  /// Meminta izin notifikasi (Android 13 ke atas). True bila diizinkan.
  Future<bool> requestPermission();

  /// Memasang notifikasi yang berulang setiap 7 hari, dihitung dari sekarang.
  Future<void> scheduleWeekly();

  Future<void> cancel();

  /// Apakah jadwal mingguan sudah terpasang.
  Future<bool> isScheduled();
}

/// Notifikasi lokal Android. Tidak butuh internet atau server.
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const notificationId = 7001;
  static const _channelId = 'backup_reminder';
  static const _channelName = 'Pengingat backup';

  @override
  Future<void> init() async {
    if (_ready) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_backup'),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> scheduleWeekly() async {
    await init();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Mengingatkan pemilik membuat backup data seminggu sekali.',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(
          'Sudah seminggu sejak backup terakhir. Bagikan atau simpan '
          'backup sekarang supaya riwayat order dan piutang tidak hilang '
          'bila HP rusak atau hilang.',
        ),
      ),
    );

    // Inexact: tidak butuh izin alarm tepat waktu. Telat beberapa menit
    // tidak masalah untuk pengingat seminggu sekali.
    await _plugin.periodicallyShow(
      id: notificationId,
      title: 'Saatnya backup data Laundry Manise',
      body: 'Sudah seminggu sejak backup terakhir. Ketuk untuk membuat '
          'backup sekarang.',
      repeatInterval: RepeatInterval.weekly,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel() async {
    await init();
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<bool> isScheduled() async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((r) => r.id == notificationId);
  }
}

/// Aturan pengingat backup mingguan.
///
/// Data aplikasi ini hanya ada di satu HP. Backup harian otomatis ada di HP
/// yang sama, jadi tidak menolong saat HP hilang. Pengingat ini memaksa
/// pemilik, seminggu sekali, membuat salinan yang ia sadari: dibagikan ke
/// luar HP atau setidaknya disimpan.
class BackupReminder {
  BackupReminder(
    this._settings, {
    ReminderScheduler? scheduler,
    DateTime Function()? clock,
  })  : _scheduler = scheduler ?? LocalNotificationScheduler(),
        _clock = clock ?? DateTime.now;

  static const intervalDays = 7;

  final SettingsRepository _settings;
  final ReminderScheduler _scheduler;
  final DateTime Function() _clock;

  BackupStatus status() {
    final now = _clock();
    final last = DateTime.tryParse(_settings.get(SettingsKeys.backupLastAt));
    final seeded = DateTime.tryParse(_settings.get(SettingsKeys.seededAt));

    return BackupStatus(
      lastAt: last,
      method: BackupMethod.fromCode(_settings.get(SettingsKeys.backupLastMethod)),
      baseline: last ?? seeded ?? now,
      now: now,
    );
  }

  /// Dipanggil setelah pemilik berhasil membuat backup. Hitungan seminggu
  /// dimulai ulang dan notifikasi berikutnya dijadwalkan 7 hari dari sekarang.
  Future<void> markDone(BackupMethod method) async {
    await _settings.setAll({
      SettingsKeys.backupLastAt: _clock().toIso8601String(),
      SettingsKeys.backupLastMethod: method.code,
    });
    await _reschedule();
  }

  /// Dipanggil tiap aplikasi dibuka. Memasang jadwal bila belum ada
  /// (pemasangan baru, atau jadwal hilang karena data aplikasi dibersihkan),
  /// tanpa mengulang hitungan yang sedang berjalan.
  Future<void> ensureScheduled() async {
    try {
      await _scheduler.init();
      if (!await _scheduler.isScheduled()) await _scheduler.scheduleWeekly();
    } catch (_) {
      // Pengingat tidak boleh menghalangi aplikasi dibuka. Kartu di beranda
      // tetap muncul walau notifikasi gagal terpasang.
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _scheduler.requestPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> _reschedule() async {
    try {
      await _scheduler.cancel();
      await _scheduler.scheduleWeekly();
    } catch (_) {
      // Lihat ensureScheduled.
    }
  }

  /// Dialog pengingat di dalam aplikasi: hanya bila terlambat, dan paling
  /// banyak sekali sehari.
  bool shouldPromptNow() {
    if (!status().overdue) return false;

    final last =
        DateTime.tryParse(_settings.get(SettingsKeys.backupPromptedAt));
    if (last == null) return true;

    final now = _clock();
    return last.year != now.year ||
        last.month != now.month ||
        last.day != now.day;
  }

  Future<void> markPrompted() => _settings.set(
        SettingsKeys.backupPromptedAt,
        _clock().toIso8601String(),
      );
}
