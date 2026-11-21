import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import 'consent_manager.dart';

/// ID unit iklan.
///
/// Nilai bawaan adalah ID UJI resmi dari Google. Memakai ID produksi selama
/// pengembangan adalah penyebab paling umum akun AdMob ditutup permanen.
///
/// ID produksi diisi saat build rilis:
///   flutter build appbundle --release \
///     --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/111 \
///     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-xxx/222 \
///     --dart-define=ADMOB_REWARDED_ID=ca-app-pub-xxx/333
abstract final class AdIds {
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static String _pick(String fromEnv, String test) {
    if (kDebugMode || fromEnv.isEmpty) return test;
    return fromEnv;
  }

  static String get banner =>
      _pick(const String.fromEnvironment('ADMOB_BANNER_ID'), _testBanner);

  static String get interstitial => _pick(
      const String.fromEnvironment('ADMOB_INTERSTITIAL_ID'), _testInterstitial);

  static String get rewarded =>
      _pick(const String.fromEnvironment('ADMOB_REWARDED_ID'), _testRewarded);
}

/// Aturan penempatan iklan di aplikasi ini.
///
/// Iklan TIDAK PERNAH muncul di layar input order, layar pembayaran, atau
/// saat proses cetak nota. Kebijakan AdMob melarang interstitial yang terpicu
/// setelah setiap klik pengguna atau yang menyela alur kerja inti, dan
/// pelanggarannya berakibat penutupan akun permanen.
///
/// Yang dilakukan kelas ini:
/// - Banner di layar daftar order dan laporan.
/// - Interstitial maksimal SEKALI per sesi pemakaian aplikasi, hanya di
///   titik transisi, tidak pernah per transaksi.
/// - Rewarded ad yang benar-benar opsional, ditukar fitur tambahan.
class AdService {
  AdService(this._settings, this.consent);

  final SettingsRepository _settings;
  final ConsentManager consent;

  bool _initialized = false;
  bool _interstitialShownThisSession = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  bool get enabled =>
      _settings.getBool(SettingsKeys.adsEnabled, fallback: true) &&
      (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (_initialized || !enabled) return;

    try {
      // Persetujuan privasi diminta SEBELUM iklan pertama. Meminta iklan
      // lebih dulu adalah pelanggaran kebijakan UMP.
      final allowed = await consent.gatherConsent();
      if (!allowed) {
        debugPrint('Pengguna tidak mengizinkan iklan. AdMob dilewati.');
        return;
      }

      await MobileAds.instance.initialize();
      _initialized = true;
      _preloadInterstitial();
      _preloadRewarded();
    } catch (e) {
      debugPrint('AdMob gagal diinisialisasi: $e');
    }
  }

  // ----------------------------------------------------------- interstitial

  void _preloadInterstitial() {
    if (!enabled) return;

    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Dipanggil sekali saja, di titik transisi setelah kasir masuk.
  ///
  /// Mengembalikan segera bila iklan belum siap: alur kerja tidak pernah
  /// menunggu iklan.
  Future<void> maybeShowSessionInterstitial() async {
    if (!enabled || _interstitialShownThisSession) return;

    final ad = _interstitial;
    if (ad == null) return;

    _interstitialShownThisSession = true;
    _interstitial = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, _) => ad.dispose(),
    );

    await ad.show();
  }

  // --------------------------------------------------------------- rewarded

  void _preloadRewarded() {
    if (!enabled) return;

    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  bool get rewardedReady => _rewarded != null;

  /// Menayangkan rewarded ad. Mengembalikan true bila pengguna menonton
  /// sampai selesai dan berhak atas hadiahnya.
  ///
  /// Pemanggil WAJIB menawarkan ini sebagai pilihan yang bisa ditolak, dan
  /// WAJIB menyediakan jalan lain untuk mencapai hasil yang sama.
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (!enabled || ad == null) return false;

    _rewarded = null;
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _preloadRewarded();
      },
    );

    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return earned;
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
  }
}

/// Banner yang menghilang sendiri bila iklan tidak tersedia.
///
/// Tidak pernah menyisakan ruang kosong saat gagal dimuat, dan selalu
/// berjarak dari tombol aktif supaya tidak memicu klik tidak sengaja.
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

    return Padding(
      // Jarak 24 di atas dan bawah menjaga iklan tidak bersentuhan dengan
      // tombol aktif mana pun.
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: _ad!.size.width.toDouble(),
          height: _ad!.size.height.toDouble(),
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}

/// Dialog tawaran rewarded ad. Tombol "Tidak sekarang" selalu ada dan
/// pengguna tetap bisa memakai fitur lewat jalan biasa.
Future<bool> offerRewardedAd(
  BuildContext context, {
  required String title,
  required String description,
  required String rewardLabel,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 12),
          Text(
            rewardLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Tidak sekarang'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Tonton iklan'),
        ),
      ],
    ),
  );

  return accepted == true;
}
