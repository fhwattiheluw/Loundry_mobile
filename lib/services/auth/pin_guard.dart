import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

/// Pembatas percobaan PIN.
///
/// PIN hanya 4 sampai 6 digit, jadi tanpa pembatas semua kemungkinannya bisa
/// dicoba dalam hitungan jam oleh siapa pun yang memegang HP konter. Setiap
/// kelima kali salah berturut-turut, layar login dikunci makin lama: 30 detik,
/// 5 menit, lalu 15 menit. Lima kesempatan pertama tidak mengganggu kasir yang
/// sekadar salah ketik.
///
/// Hitungannya disimpan di database, jadi menutup lalu membuka aplikasi tidak
/// mengulangnya dari nol.
class PinGuard {
  PinGuard(this._settings, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const attemptsPerRound = 5;

  final SettingsRepository _settings;
  final DateTime Function() _clock;

  int get failures => _settings.getInt(SettingsKeys.pinFailures);

  /// Sisa waktu kunci. Null bila layar tidak terkunci.
  Duration? lockRemaining() {
    final until = DateTime.tryParse(_settings.get(SettingsKeys.pinLockedUntil));
    if (until == null) return null;

    final left = until.difference(_clock());
    return left > Duration.zero ? left : null;
  }

  /// Sisa kesempatan sebelum kunci berikutnya.
  int get attemptsLeftInRound => attemptsPerRound - (failures % attemptsPerRound);

  /// Lama kunci setelah kegagalan ke-[failures]. Nol bila belum waktunya.
  static Duration lockFor(int failures) {
    if (failures <= 0 || failures % attemptsPerRound != 0) return Duration.zero;

    return switch (failures ~/ attemptsPerRound) {
      1 => const Duration(seconds: 30),
      2 => const Duration(minutes: 5),
      _ => const Duration(minutes: 15),
    };
  }

  /// Mencatat PIN salah. Mengembalikan lama kunci yang baru dipasang,
  /// atau [Duration.zero] bila belum terkunci.
  Future<Duration> recordFailure() async {
    final count = failures + 1;
    final lock = lockFor(count);

    await _settings.setAll({
      SettingsKeys.pinFailures: '$count',
      if (lock > Duration.zero)
        SettingsKeys.pinLockedUntil: _clock().add(lock).toIso8601String(),
    });

    return lock;
  }

  /// PIN benar: hitungan dan kunci dibersihkan.
  Future<void> recordSuccess() async {
    if (failures == 0 && _settings.get(SettingsKeys.pinLockedUntil).isEmpty) {
      return;
    }

    await _settings.setAll({
      SettingsKeys.pinFailures: '0',
      SettingsKeys.pinLockedUntil: '',
    });
  }

  /// "30 detik", "5 menit". Dibulatkan ke atas supaya tidak pernah
  /// menjanjikan waktu yang lebih singkat dari kenyataan.
  static String describe(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds < 1 ? 1 : d.inSeconds} detik';
    return '${(d.inSeconds / 60).ceil()} menit';
  }
}
