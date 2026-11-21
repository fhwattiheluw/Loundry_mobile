import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

/// ID unit iklan.
///
/// PENTING: nilai di bawah adalah ID UJI resmi dari Google. Memakai ID
/// produksi selama pengembangan adalah penyebab paling umum akun AdMob
/// ditutup permanen (FR-117).
///
/// Ganti ID produksi lewat --dart-define saat build rilis:
///   flutter build apk --release \
///     --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxxx/yyyy
abstract final class AdIds {
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';

  static String get banner {
    const fromEnv = String.fromEnvironment('ADMOB_BANNER_ID');
    if (fromEnv.isEmpty || kDebugMode) return _testBanner;
    return fromEnv;
  }
}

/// Iklan tidak boleh mengganggu pekerjaan kasir.
///
/// Aturan yang dipegang kelas ini:
/// - Tidak pernah tampil di layar input order, pembayaran, atau saat mencetak.
/// - Saat offline atau gagal dimuat, area iklan hilang sepenuhnya,
///   tanpa menyisakan ruang kosong (FR-114).
class AdService {
  AdService(this._settings);

  final SettingsRepository _settings;

  bool _initialized = false;

  bool get enabled =>
      _settings.getBool(SettingsKeys.adsEnabled, fallback: true) &&
      (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (_initialized || !enabled) return;

    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('AdMob gagal diinisialisasi: $e');
    }
  }
}

/// Banner yang menghilang sendiri bila iklan tidak tersedia.
class SafeBannerAd extends StatefulWidget {
  const SafeBannerAd({super.key, required this.enabled});

  final bool enabled;

  @override
  State<SafeBannerAd> createState() => _SafeBannerAdState();
}

class _SafeBannerAdState extends State<SafeBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Offline atau tidak ada iklan. Diamkan: area iklan tetap kosong
          // dan kasir tidak melihat pesan error apa pun.
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    // Jarak 16 di atas dan bawah menjaga iklan tidak bersentuhan dengan
    // tombol aktif, sesuai FR-115.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        width: _ad!.size.width.toDouble(),
        height: _ad!.size.height.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
