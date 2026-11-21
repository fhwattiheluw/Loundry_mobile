import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Persetujuan privasi lewat Google User Messaging Platform (FR-116).
///
/// Wajib untuk pengguna di wilayah yang mengharuskannya, misalnya Uni Eropa
/// dan Inggris. Tanpa ini, permintaan iklan dari wilayah tersebut ditolak
/// dan aplikasi berisiko ditolak saat peninjauan Play Store.
///
/// Untuk pengguna Indonesia, UMP umumnya tidak memunculkan dialog apa pun,
/// jadi kasir tidak melihat perbedaan apa-apa.
class ConsentManager {
  ConsentManager();

  bool _requested = false;

  /// Meminta status persetujuan dan menampilkan formulir bila diperlukan.
  ///
  /// Mengembalikan true bila iklan boleh diminta. Setiap kegagalan dianggap
  /// "boleh", karena UMP sendiri akan membatasi iklan yang dikirim; memblokir
  /// iklan di sisi aplikasi hanya akan menghilangkan pendapatan tanpa
  /// menambah perlindungan apa pun.
  Future<bool> gatherConsent() async {
    if (_requested) return canRequestAds();
    _requested = true;

    final params = ConsentRequestParameters(
      // Aplikasi kasir ini bukan untuk anak-anak.
      tagForUnderAgeOfConsent: false,
    );

    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (error != null) {
              debugPrint('Formulir persetujuan gagal: ${error.message}');
            }
            finish();
          });
        } catch (e) {
          debugPrint('Formulir persetujuan gagal dimuat: $e');
          finish();
        }
      },
      (error) {
        debugPrint('Status persetujuan gagal diambil: ${error.message}');
        finish();
      },
    );

    // Batas waktu supaya aplikasi tidak pernah menggantung menunggu UMP,
    // misalnya saat jaringan sangat lambat.
    await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => debugPrint('UMP tidak merespons, iklan dilanjutkan.'),
    );

    return canRequestAds();
  }

  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return true;
    }
  }

  /// Memungkinkan pemilik membuka ulang pilihan privasinya dari Pengaturan,
  /// yang juga merupakan syarat kepatuhan UMP.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) {
          debugPrint('Opsi privasi gagal dibuka: ${error.message}');
        }
      });
    } catch (e) {
      debugPrint('Opsi privasi gagal dibuka: $e');
    }
  }

  /// Hanya untuk pengujian di perangkat pengembang.
  Future<void> reset() async {
    _requested = false;
    try {
      await ConsentInformation.instance.reset();
    } catch (_) {
      // Tidak penting di luar pengembangan.
    }
  }
}
