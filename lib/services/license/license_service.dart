import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

/// Keadaan langganan aplikasi.
enum LicenseState {
  /// Masa coba gratis, masih berjalan.
  trial,

  /// Langganan aktif, atau masih dalam masa tenggang luring.
  active,

  /// Masa coba atau langganan sudah lewat.
  expired,

  /// Jam perangkat dimundurkan. Harus daring untuk memastikan ulang.
  clockTampered,
}

class LicenseStatus {
  const LicenseStatus(this.state, {this.until, this.daysLeft = 0});

  final LicenseState state;
  final DateTime? until;
  final int daysLeft;

  bool get canUseApp =>
      state == LicenseState.trial || state == LicenseState.active;
}

/// Mengatur masa pakai aplikasi: coba gratis, langganan bulanan, dan masa
/// tenggang saat tidak ada internet.
///
/// Aturannya dibuat longgar dengan sengaja. Aplikasi ini dipakai di konter
/// yang jaringannya mati berjam-jam, dan kasir yang tidak bisa menerima
/// cucian karena langganan "belum terverifikasi" adalah kegagalan yang
/// jauh lebih mahal daripada sebulan langganan yang terlewat ditagih.
class LicenseService {
  LicenseService(this._settings);

  final SettingsRepository _settings;

  /// Masa coba gratis sejak aplikasi pertama kali dibuka.
  static const trialDays = 30;

  /// Berapa lama langganan dianggap masih berlaku sejak terakhir kali Play
  /// Store mengabarkan ia aktif. Lebih panjang dari satu siklus tagihan,
  /// supaya perangkat yang sebulan penuh luring tidak ikut terkunci.
  static const offlineGraceDays = 35;

  /// Toleransi jam mundur. Zona waktu dan jam yang dikoreksi sendiri oleh
  /// sistem bisa menggeser waktu beberapa jam; itu bukan kecurangan.
  static const _clockToleranceHours = 26;

  /// Harus dipanggil sekali saat aplikasi dibuka, sebelum [status] dibaca.
  Future<void> init() async {
    final now = DateTime.now();

    if (_settings.get(SettingsKeys.trialStartedAt).isEmpty) {
      await _settings.set(
          SettingsKeys.trialStartedAt, now.toIso8601String());
    }

    final seen = _dateOf(SettingsKeys.clockLastSeen);
    if (seen == null || now.isAfter(seen)) {
      await _settings.set(SettingsKeys.clockLastSeen, now.toIso8601String());
    }
  }

  /// Dipanggil saat Play Store mengabarkan langganan aktif.
  Future<void> markVerified() async {
    final now = DateTime.now();
    await _settings.setAll({
      SettingsKeys.licenseLastVerified: now.toIso8601String(),
      SettingsKeys.licenseActiveUntil:
          now.add(const Duration(days: offlineGraceDays)).toIso8601String(),
      // Verifikasi dari Play Store juga menyembuhkan tuduhan jam mundur:
      // keadaan langganan baru saja dipastikan dari sumber yang benar.
      SettingsKeys.clockLastSeen: now.toIso8601String(),
    });
  }

  /// Dipanggil saat Play Store mengabarkan langganan sudah tidak aktif.
  Future<void> markInactive() async {
    await _settings.set(SettingsKeys.licenseActiveUntil, '');
  }

  LicenseStatus get status {
    final now = DateTime.now();

    final activeUntil = _dateOf(SettingsKeys.licenseActiveUntil);
    final isSubscribed = activeUntil != null && now.isBefore(activeUntil);

    final seen = _dateOf(SettingsKeys.clockLastSeen);
    final clockMovedBack = seen != null &&
        now.isBefore(seen.subtract(const Duration(hours: _clockToleranceHours)));

    // Jam mundur hanya menjadi masalah bila ia dipakai menghidupkan kembali
    // masa pakai yang sudah habis. Pelanggan yang langganannya aktif tidak
    // perlu diganggu karena mengubah zona waktu.
    if (clockMovedBack && !isSubscribed) {
      return const LicenseStatus(LicenseState.clockTampered);
    }

    if (isSubscribed) {
      return LicenseStatus(
        LicenseState.active,
        until: activeUntil,
        daysLeft: activeUntil.difference(now).inDays,
      );
    }

    final trialStart = _dateOf(SettingsKeys.trialStartedAt);

    // Belum tercatat berarti aplikasi baru pertama kali dibuka, atau init()
    // belum sempat menulis. Keduanya harus dibaca sebagai masa coba yang
    // baru mulai: pemasangan baru tidak boleh langsung disambut tagihan.
    if (trialStart == null) {
      return LicenseStatus(
        LicenseState.trial,
        until: now.add(const Duration(days: trialDays)),
        daysLeft: trialDays,
      );
    }

    final trialEnd = trialStart.add(const Duration(days: trialDays));
    if (now.isBefore(trialEnd)) {
      return LicenseStatus(
        LicenseState.trial,
        until: trialEnd,
        daysLeft: trialEnd.difference(now).inDays + 1,
      );
    }

    return const LicenseStatus(LicenseState.expired);
  }

  DateTime? _dateOf(String key) {
    final raw = _settings.get(key);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
