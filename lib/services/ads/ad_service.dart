import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import 'ad_config.dart';
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
  static const _testAppOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const _testNative = 'ca-app-pub-3940256099942544/2247696110';

  /// Urutan prioritas: mode debug selalu uji; lalu --dart-define; lalu
  /// [AdConfig]; terakhir ID uji.
  static String _pick(String fromEnv, String fromConfig, String test) {
    if (kDebugMode) return test;
    if (fromEnv.isNotEmpty) return fromEnv;
    if (fromConfig.isNotEmpty) return fromConfig;
    return test;
  }

  static String get banner => _pick(
      const String.fromEnvironment('ADMOB_BANNER_ID'),
      AdConfig.banner,
      _testBanner);

  static String get interstitial => _pick(
      const String.fromEnvironment('ADMOB_INTERSTITIAL_ID'),
      AdConfig.interstitial,
      _testInterstitial);

  static String get rewarded => _pick(
      const String.fromEnvironment('ADMOB_REWARDED_ID'),
      AdConfig.rewarded,
      _testRewarded);

  static String get appOpen => _pick(
      const String.fromEnvironment('ADMOB_APP_OPEN_ID'),
      AdConfig.appOpen,
      _testAppOpen);

  static String get native => _pick(
      const String.fromEnvironment('ADMOB_NATIVE_ID'),
      AdConfig.native,
      _testNative);

  /// True bila ID yang dipakai bukan ID uji Google.
  static bool _isReal(String id) => !id.startsWith('ca-app-pub-3940256099942544');

  /// Jenis unit yang SUDAH memakai ID produksi, dan yang MASIH uji.
  static Map<String, bool> get realByFormat => {
        'Banner': _isReal(banner),
        'Native': _isReal(native),
        'Interstitial': _isReal(interstitial),
        'App open': _isReal(appOpen),
        'Rewarded': _isReal(rewarded),
      };

  /// Semua unit memakai ID produksi. Hanya dalam keadaan inilah iklan
  /// menghasilkan uang.
  static bool get allProduction => realByFormat.values.every((v) => v);

  /// Tidak ada satu pun ID produksi. Build rilis dalam keadaan ini hanya
  /// menayangkan iklan uji dan pendapatannya nol.
  static bool get allTest => realByFormat.values.every((v) => !v);
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

  /// True setelah persetujuan terkumpul dan SDK selesai diinisialisasi.
  /// Banner dan iklan native menunggu ini sebelum meminta iklan: meminta
  /// sebelum SDK siap membuat permintaan gagal, dan meminta sebelum
  /// persetujuan adalah pelanggaran kebijakan UMP.
  static final ValueNotifier<bool> sdkReady = ValueNotifier(false);

  /// Hasil muat terakhir tiap jenis iklan, untuk layar Status iklan.
  static final ValueNotifier<Map<String, String>> report = ValueNotifier({});

  static void note(String key, String value) {
    report.value = {...report.value, key: value};
  }

  /// Muat ulang otomatis bila iklan gagal. Tanpa ini, satu kegagalan
  /// ("no fill" itu normal, terutama pada unit baru) membuat jenis iklan
  /// tersebut mati sampai aplikasi dibuka ulang.
  static const _maxRetries = 6;
  final _retryCount = <String, int>{};
  final _retryTimers = <String, Timer>{};

  void _scheduleRetry(String key, VoidCallback load) {
    final n = (_retryCount[key] ?? 0) + 1;
    _retryCount[key] = n;
    if (n > _maxRetries) return;

    // 30 dtk, 1 mnt, 2 mnt, 4 mnt, lalu 5 mnt.
    final seconds = (30 * (1 << (n - 1))).clamp(30, 300).toInt();
    _retryTimers[key]?.cancel();
    _retryTimers[key] = Timer(Duration(seconds: seconds), load);
  }

  void _loaded(String key) {
    _retryCount[key] = 0;
    note(key, 'Siap');
  }

  bool _initStarted = false;
  bool _initialized = false;
  bool _interstitialShownThisSession = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  AppOpenAd? _appOpen;
  DateTime? _appOpenLoadedAt;
  bool _appOpenListening = false;

  /// True selama ada iklan layar penuh yang sedang tampil, apa pun
  /// jenisnya. Dua iklan layar penuh yang bertumpuk adalah pelanggaran
  /// kebijakan sekaligus cara tercepat membuat orang mencopot aplikasi.
  bool _showingFullScreen = false;

  /// Kapan interstitial terakhir tampil. Jeda minimum menahan dua iklan
  /// berturut-turut ketika kasir menutup shift lalu langsung mencetak
  /// laporan.
  DateTime? _lastInterstitialAt;

  static const _minInterstitialGap = Duration(minutes: 4);

  /// Iklan pembuka baru dinyalakan setelah aplikasi dibuka sekian kali.
  /// Menyambut pengguna baru dengan iklan layar penuh di hari pertama
  /// adalah cara kehilangan mereka sebelum sempat mencoba.
  static const _appOpenMinLaunches = 4;

  /// Iklan SELALU menyala. Aplikasi ini gratis dan seluruh pendapatannya
  /// berasal dari iklan, jadi tidak ada sakelar, tidak ada pembelian bebas
  /// iklan, dan tidak ada pengaturan yang bisa mematikannya.
  bool get enabled => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (_initialized || _initStarted || !enabled) return;
    _initStarted = true;

    try {
      // Persetujuan privasi diminta SEBELUM iklan pertama. Meminta iklan
      // lebih dulu adalah pelanggaran kebijakan UMP.
      note('Persetujuan', 'Memeriksa...');
      final allowed = await consent.gatherConsent();
      if (!allowed) {
        note('Persetujuan', 'Belum mengizinkan iklan');
        debugPrint('Pengguna tidak mengizinkan iklan. AdMob dilewati.');
        _initStarted = false;
        return;
      }
      note('Persetujuan', 'OK');

      await MobileAds.instance.initialize();
      _initialized = true;
      sdkReady.value = true;
      note('SDK', 'Siap');

      _preloadInterstitial();
      _preloadRewarded();
      await _startAppOpen();
    } catch (e) {
      note('SDK', 'Gagal: $e');
      debugPrint('AdMob gagal diinisialisasi: $e');
      _initStarted = false;
    }
  }

  /// Memuat ulang semua iklan layar penuh. Dipakai tombol di layar Status
  /// iklan untuk memeriksa ulang setelah ID produksi diganti.
  void reloadAll() {
    if (!_initialized) {
      init();
      return;
    }
    _retryCount.clear();
    _preloadInterstitial();
    _preloadRewarded();
    _loadAppOpen();
  }

  // ----------------------------------------------------------- interstitial

  void _preloadInterstitial() {
    if (!enabled) return;

    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loaded('Interstitial');
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          note('Interstitial', 'Gagal (${error.code}): ${error.message}');
          _scheduleRetry('Interstitial', _preloadInterstitial);
        },
      ),
    );
  }

  /// Dipanggil sekali saja, di titik transisi setelah kasir masuk.
  ///
  /// Iklan baru mulai dimuat setelah persetujuan dan SDK siap, jadi saat
  /// dipanggil ia biasanya belum ada. Fungsi ini menunggu sebentar (tanpa
  /// menahan layar) dan hanya menayangkan bila [canShow] masih mengizinkan,
  /// misalnya kasir belum membuka layar lain. Bila waktu habis, iklan
  /// dilewati; tidak ada yang menunggu iklan.
  Future<void> maybeShowSessionInterstitial({bool Function()? canShow}) async {
    if (!enabled || _interstitialShownThisSession) return;

    for (var i = 0; i < 20 && _interstitial == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!enabled) return;
    }

    final ad = _interstitial;
    if (ad == null || _showingFullScreen) return;
    if (canShow != null && !canShow()) return;

    _interstitialShownThisSession = true;
    _interstitial = null;
    _lastInterstitialAt = DateTime.now();
    _showingFullScreen = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadInterstitial();
      },
    );

    await _safeShow(ad.show, ad, onFailed: _preloadInterstitial);
  }

  /// Menayangkan interstitial di titik jeda yang disebut [reason].
  ///
  /// Dipakai setelah tutup shift dan setelah laporan tercetak: dua momen
  /// ketika kasir memang sedang berhenti bekerja. TIDAK BOLEH dipanggil
  /// dari alur order, pembayaran, atau cetak nota.
  Future<void> showInterstitialAt(String reason) async {
    if (!enabled || _showingFullScreen) return;

    final last = _lastInterstitialAt;
    if (last != null &&
        DateTime.now().difference(last) < _minInterstitialGap) {
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _interstitial = null;
    _lastInterstitialAt = DateTime.now();
    _showingFullScreen = true;
    debugPrint('Interstitial ditampilkan: $reason');

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadInterstitial();
      },
    );

    await _safeShow(ad.show, ad, onFailed: _preloadInterstitial);
  }

  // --------------------------------------------------------- iklan pembuka

  /// Iklan yang tampil saat aplikasi kembali dari latar belakang.
  ///
  /// Kasir membuka aplikasi ini puluhan kali sehari, jadi inilah penempatan
  /// dengan tayangan terbanyak. Aturan Google yang dipatuhi di sini:
  /// tidak tampil saat aplikasi pertama kali dijalankan, tidak tampil di
  /// atas iklan lain, dan iklan yang lebih tua dari empat jam dibuang
  /// karena sudah tidak bernilai.
  Future<void> _startAppOpen() async {
    if (_appOpenListening || !enabled) return;

    final opens =
        int.tryParse(_settings.get(SettingsKeys.appOpenCount)) ?? 0;
    await _settings.set(SettingsKeys.appOpenCount, '${opens + 1}');
    if (opens + 1 < _appOpenMinLaunches) return;

    _appOpenListening = true;
    _loadAppOpen();

    AppStateEventNotifier.startListening();
    AppStateEventNotifier.appStateStream.forEach((state) {
      // Hanya saat kembali dari latar. Pembukaan dingin tidak ikut, karena
      // di situ pengguna sudah berada di layar isi, dan Google melarang
      // iklan pembuka di titik itu.
      if (state == AppState.foreground) _showAppOpenIfReady();
    });
  }

  void _loadAppOpen() {
    if (!enabled) return;

    AppOpenAd.load(
      adUnitId: AdIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpen = ad;
          _appOpenLoadedAt = DateTime.now();
          _loaded('App open');
        },
        onAdFailedToLoad: (error) {
          _appOpen = null;
          note('App open', 'Gagal (${error.code}): ${error.message}');
          _scheduleRetry('App open', _loadAppOpen);
        },
      ),
    );
  }

  void _showAppOpenIfReady() {
    if (!enabled || _showingFullScreen) return;

    final ad = _appOpen;
    final loadedAt = _appOpenLoadedAt;
    if (ad == null || loadedAt == null) {
      _loadAppOpen();
      return;
    }

    // Iklan pembuka kedaluwarsa setelah empat jam dan tidak lagi
    // menghasilkan. Dibuang, bukan ditayangkan.
    if (DateTime.now().difference(loadedAt) > const Duration(hours: 4)) {
      ad.dispose();
      _appOpen = null;
      _loadAppOpen();
      return;
    }

    _appOpen = null;
    _showingFullScreen = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingFullScreen = false;
        ad.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingFullScreen = false;
        ad.dispose();
        _loadAppOpen();
      },
    );

    unawaited(_safeShow(ad.show, ad, onFailed: _loadAppOpen));
  }

  // --------------------------------------------------------------- rewarded

  void _preloadRewarded() {
    if (!enabled) return;

    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loaded('Rewarded');
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          note('Rewarded', 'Gagal (${error.code}): ${error.message}');
          _scheduleRetry('Rewarded', _preloadRewarded);
        },
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
    if (!enabled || ad == null || _showingFullScreen) return false;

    _rewarded = null;
    _showingFullScreen = true;
    var earned = false;

    // ad.show() selesai begitu iklan MUNCUL, bukan saat ditutup: plugin
    // Android langsung menjawab setelah menampilkan iklan. Dulu nilai
    // earned dibaca saat itu, selalu false, sehingga ekspor PDF dibatalkan
    // tepat ketika iklan baru mulai, dan pemilik yang menonton sampai
    // "Reward diberikan" tidak mendapat apa-apa. Hasilnya kini diambil
    // ketika iklan benar-benar ditutup.
    final closed = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadRewarded();
        if (!closed.isCompleted) closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingFullScreen = false;
        ad.dispose();
        _preloadRewarded();
        if (!closed.isCompleted) closed.complete(false);
      },
    );

    final shown = await _safeShow(
      () => ad.show(onUserEarnedReward: (_, __) => earned = true),
      ad,
      onFailed: _preloadRewarded,
    );
    if (!shown) return false;

    return closed.future;
  }

  /// Menjalankan show() tanpa membiarkan kegagalannya mengunci aplikasi.
  ///
  /// Bila Android gagal menampilkan iklan, plugin melempar galat dan
  /// callback onAdFailedToShowFullScreenContent tidak dipanggil. Tanpa ini
  /// [_showingFullScreen] tertinggal true selamanya dan semua iklan layar
  /// penuh berikutnya diam-diam tidak pernah tampil.
  Future<bool> _safeShow(
    Future<void> Function() show,
    Ad ad, {
    required void Function() onFailed,
  }) async {
    try {
      await show();
      return true;
    } catch (e) {
      debugPrint('Iklan gagal ditampilkan: $e');
      _showingFullScreen = false;
      ad.dispose();
      onFailed();
      return false;
    }
  }

  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpen?.dispose();
  }
}

/// Banner yang menghilang sendiri bila iklan tidak tersedia.
///
/// Menunggu SDK siap sebelum meminta iklan, dan mencoba lagi dengan jeda
/// bila gagal. Tidak pernah menyisakan ruang kosong saat belum ada iklan.
class SafeBannerAd extends StatefulWidget {
  const SafeBannerAd({super.key, required this.enabled, this.compact = false});

  final bool enabled;

  /// Jarak tipis, untuk banner yang menempel di atas bilah navigasi.
  final bool compact;

  @override
  State<SafeBannerAd> createState() => _SafeBannerAdState();
}

class _SafeBannerAdState extends State<SafeBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;
  int _failures = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    AdService.sdkReady.addListener(_maybeLoad);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!mounted || !widget.enabled || _ad != null) return;
    if (!AdService.sdkReady.value) return;
    _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _failures = 0;
          AdService.note('Banner', 'Siap');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          AdService.note('Banner', 'Gagal (${error.code}): ${error.message}');
          if (mounted) setState(() => _loaded = false);

          // Coba lagi dengan jeda yang membesar: 30 dtk sampai 5 mnt.
          _failures++;
          if (_failures <= 6) {
            final seconds = (30 * (1 << (_failures - 1))).clamp(30, 300);
            _retry?.cancel();
            _retry = Timer(Duration(seconds: seconds.toInt()), _maybeLoad);
          }
        },
      ),
    );

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    AdService.sdkReady.removeListener(_maybeLoad);
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      // Jarak menjaga iklan tidak bersentuhan dengan tombol aktif mana pun.
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 6 : 24),
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

/// Iklan native yang menyatu dengan daftar order.
///
/// Dipakai sebagai pengganti banner di dalam daftar: bentuknya mengikuti
/// kartu di sekitarnya, jadi ia terbaca sebagai bagian halaman alih-alih
/// spanduk yang ditempel. Label "Iklan" dari Google tetap tampil, dan itu
/// memang wajib.
///
/// Memakai template bawaan plugin, jadi tidak ada kode Android tambahan
/// yang harus dirawat. Menunggu SDK siap, mencoba lagi bila gagal, dan
/// hilang sama sekali bila memang tidak ada iklan.
class SafeNativeAd extends StatefulWidget {
  const SafeNativeAd({super.key, required this.enabled});

  final bool enabled;

  @override
  State<SafeNativeAd> createState() => _SafeNativeAdState();
}

class _SafeNativeAdState extends State<SafeNativeAd> {
  NativeAd? _ad;
  bool _loaded = false;
  int _failures = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    AdService.sdkReady.addListener(_maybeLoad);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!mounted || !widget.enabled || _ad != null) return;
    if (!AdService.sdkReady.value) return;
    _load();
  }

  void _load() {
    final ad = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        cornerRadius: 14,
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _failures = 0;
          AdService.note('Native', 'Siap');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          AdService.note('Native', 'Gagal (${error.code}): ${error.message}');
          if (mounted) setState(() => _loaded = false);

          _failures++;
          if (_failures <= 6) {
            final seconds = (30 * (1 << (_failures - 1))).clamp(30, 300);
            _retry?.cancel();
            _retry = Timer(Duration(seconds: seconds.toInt()), _maybeLoad);
          }
        },
      ),
    );

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    AdService.sdkReady.removeListener(_maybeLoad);
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        // Tinggi template kecil menurut Google. Tanpa batas ini, AdWidget
        // di dalam daftar yang menggulung akan melempar galat tata letak.
        constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
        child: AdWidget(ad: _ad!),
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
