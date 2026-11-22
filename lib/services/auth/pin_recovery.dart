import 'dart:math';

import '../../core/security.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/master_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../notification/notification_service.dart';
import '../notification/whatsapp_api_sender.dart';

/// Pemulihan PIN pemilik yang terlupa.
///
/// PIN tidak pernah bisa dikirim ulang, dan itu disengaja: yang tersimpan
/// hanyalah hasil pengacakannya, bukan PIN-nya. Database yang menyimpan PIN
/// apa adanya berarti siapa pun yang bisa membuka berkasnya tahu PIN semua
/// kasir. Jadi yang dilakukan di sini bukan mengirim PIN lama, melainkan
/// membuktikan bahwa orang di depan layar memang pemiliknya, lalu
/// mempersilakan ia memasang PIN baru.
///
/// Ada dua cara membuktikannya, dan keduanya dibutuhkan.
///
/// **Kode lewat WhatsApp** hanya tersedia bila notifikasi dipasang dalam
/// mode API, karena di mode itu pesan dikirim dari server Meta ke nomor
/// pemilik, dan kodenya tidak pernah muncul di layar HP. Mode manual tidak
/// bisa dipakai di sini: ia menyusun pesan di HP yang sama, sehingga siapa
/// pun yang memegang HP akan membaca kodenya sendiri, dan kunci PIN pemilik
/// kehilangan seluruh gunanya.
///
/// **Kode pemulihan** adalah jalan yang selalu ada. Ia dibuat sekali saat
/// pengaturan awal dan dicatat pemilik di tempat aman, persis seperti kode
/// cadangan akun bank.
class PinRecoveryService {
  PinRecoveryService(this._settings, this._users, this._api);

  final SettingsRepository _settings;
  final UserRepository _users;
  final WhatsAppApiSender _api;

  /// Kode kedaluwarsa cukup cepat. Kode yang berlaku selamanya sama saja
  /// dengan PIN kedua yang tidak pernah diganti.
  static const _codeLifetime = Duration(minutes: 15);

  final _random = Random.secure();

  // ------------------------------------------------------ kode pemulihan

  bool get hasRecoveryCode =>
      _settings.get(SettingsKeys.recoveryCodeHash).isNotEmpty;

  /// Membuat kode pemulihan baru dan mengembalikannya satu kali.
  ///
  /// Nilai kembaliannya tidak pernah bisa dibaca lagi setelah ini: yang
  /// disimpan hanya hasil pengacakannya. Pemanggil wajib menampilkannya ke
  /// pemilik dan memintanya mencatat.
  Future<String> generateRecoveryCode() async {
    final code = _digits(10);
    await _settings.set(SettingsKeys.recoveryCodeHash, hashPin(code));
    return code;
  }

  bool verifyRecoveryCode(String code) {
    final hash = _settings.get(SettingsKeys.recoveryCodeHash);
    if (hash.isEmpty) return false;
    return verifyPin(code.replaceAll(RegExp(r'[^0-9]'), ''), hash);
  }

  // --------------------------------------------------------- kode WhatsApp

  /// Nomor WhatsApp pemilik, diambil dari profil usaha.
  String get ownerPhone => _settings.get(SettingsKeys.businessPhone);

  /// Hanya mode API yang aman untuk ini. Alasannya ada di dokumentasi kelas.
  bool get canSendViaWhatsApp => _api.isConfigured && ownerPhone.isNotEmpty;

  /// Nomor yang disamarkan untuk ditampilkan, misalnya "••••0373".
  String get maskedOwnerPhone {
    final digits = ownerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return '••••';
    return '••••${digits.substring(digits.length - 4)}';
  }

  Future<NotificationResult> sendResetCode() async {
    if (!canSendViaWhatsApp) {
      return const NotificationResult.failed(
        'Pengiriman kode lewat WhatsApp hanya tersedia bila notifikasi '
        'dipasang dalam mode API, dan nomor usaha sudah diisi.',
      );
    }

    final code = _digits(6);
    final expires = DateTime.now().add(_codeLifetime);

    await _settings.setAll({
      SettingsKeys.pinResetCodeHash: hashPin(code),
      SettingsKeys.pinResetExpiresAt: expires.toIso8601String(),
    });

    final result = await _api.send(
      phone: ownerPhone,
      message: 'Kode pemulihan PIN pemilik: $code\n\n'
          'Berlaku 15 menit. Jangan berikan kode ini kepada siapa pun, '
          'termasuk kasir Anda sendiri.',
    );

    // Pengiriman gagal berarti kodenya tidak sampai ke mana-mana, jadi
    // jangan tinggalkan kode hidup yang bisa ditebak belakangan.
    if (!result.sent) {
      await _settings.setAll({
        SettingsKeys.pinResetCodeHash: '',
        SettingsKeys.pinResetExpiresAt: '',
      });
    }

    return result;
  }

  bool verifyResetCode(String code) {
    final hash = _settings.get(SettingsKeys.pinResetCodeHash);
    if (hash.isEmpty) return false;

    final until = DateTime.tryParse(_settings.get(SettingsKeys.pinResetExpiresAt));
    if (until == null || DateTime.now().isAfter(until)) return false;

    return verifyPin(code.replaceAll(RegExp(r'[^0-9]'), ''), hash);
  }

  // ------------------------------------------------------------- penggantian

  /// Mengganti PIN pemilik pertama. Memanggil ini TANPA memverifikasi salah
  /// satu kode di atas lebih dulu akan membuka seluruh laporan dan harga
  /// kepada siapa pun yang memegang HP.
  Future<void> resetOwnerPin(String newPin) async {
    final owner = await _users.firstOwner();
    if (owner == null) return;

    await _users.setPin(owner.id!, newPin);

    // Kode sekali pakai memang sekali pakai.
    await _settings.setAll({
      SettingsKeys.pinResetCodeHash: '',
      SettingsKeys.pinResetExpiresAt: '',
    });
  }

  String _digits(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }
}
