import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keadaan jaringan menurut aplikasi ini.
///
/// Namanya sengaja bukan ConnectionState: Flutter sudah punya enum dengan
/// nama itu di async.dart, yang ikut terbawa setiap kali material.dart
/// diimpor. Dua enum bernama sama membuat kompilasi berhenti di berkas mana
/// pun yang memakai keduanya.
enum NetworkStatus { checking, online, offline }

/// Memeriksa koneksi internet sungguhan, bukan sekadar status antarmuka.
///
/// `connectivity_plus` hanya melaporkan apakah Wi-Fi atau data seluler aktif.
/// Perangkat bisa tersambung ke Wi-Fi hotspot yang sama sekali tidak punya
/// jalan keluar ke internet, dan kasir akan mengira aplikasi rusak. Karena itu
/// setiap perubahan status disusul satu pemeriksaan DNS singkat.
class ConnectionController extends StateNotifier<NetworkStatus> {
  ConnectionController() : super(NetworkStatus.checking) {
    // Android melaporkan "perubahan jaringan" jauh lebih sering daripada
    // koneksi benar-benar putus: kekuatan sinyal berubah, Wi-Fi dan 4G
    // bergantian, atau iklan layar penuh dibuka. Laporan yang beruntun
    // diredam dulu supaya cukup diperiksa sekali.
    _subscription = Connectivity().onConnectivityChanged.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), check);
    });
    check();
  }

  StreamSubscription<Object?>? _subscription;
  Timer? _retryTimer;
  Timer? _debounce;
  bool _running = false;

  /// Kegagalan berturut-turut selagi status masih online.
  int _strikes = 0;

  static const _probeHosts = ['google.com', 'cloudflare.com'];

  /// Memeriksa ulang koneksi.
  ///
  /// Status tidak pernah dikembalikan ke [NetworkStatus.checking]. Dulu
  /// setiap pemeriksaan ulang menyetelnya, dan gerbang di atas langsung
  /// mengganti seluruh aplikasi dengan layar "memeriksa koneksi": layar
  /// yang sedang dibuka ikut dibongkar, isian Order Baru hilang, dan ekspor
  /// laporan yang sedang menunggu iklan selesai berhenti tanpa kabar.
  /// Sekarang pemeriksaan berjalan di latar dan tampilan baru berubah bila
  /// hasilnya memang berubah.
  Future<void> check() async {
    if (_running) return;
    _running = true;

    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);

      if (hasInterface && await _canReachInternet()) {
        _strikes = 0;
        _retryTimer?.cancel();
        if (mounted) state = NetworkStatus.online;
        return;
      }

      // Satu kegagalan selagi online belum berarti putus: perpindahan Wi-Fi
      // ke data seluler sempat tanpa jaringan sesaat. Diperiksa sekali
      // lagi tiga detik kemudian sebelum layar luring ditampilkan.
      if (state == NetworkStatus.online && _strikes == 0) {
        _strikes = 1;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 3), check);
        return;
      }

      _goOffline();
    } finally {
      _running = false;
    }
  }

  void _goOffline() {
    _strikes = 0;
    if (!mounted) return;
    state = NetworkStatus.offline;

    // Coba lagi sendiri tiap 10 detik, supaya kasir tidak perlu menekan
    // tombol berulang kali saat sinyal baru pulih.
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 10), check);
  }

  Future<bool> _canReachInternet() async {
    for (final host in _probeHosts) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 4));

        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _retryTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionController, NetworkStatus>(
  (ref) => ConnectionController(),
);

/// Pembungkus yang menutup seluruh aplikasi saat internet terputus.
///
/// Aplikasi ini dijalankan dengan [requireInternet] bernilai true, lihat
/// app.dart: pendapatan sepenuhnya dari iklan, dan iklan tidak bisa dimuat
/// tanpa internet.
///
/// Ini keputusan bisnis, bukan keterbatasan teknis. Seluruh lapisan data
/// aplikasi sanggup bekerja tanpa internet, dan satu baris di app.dart
/// cukup untuk membuka kembali pemakaian luring.
///
/// Dipasang di MaterialApp.builder, membungkus Navigator, sehingga layar
/// luring menutupi semua halaman yang sedang terbuka. Setelah aplikasi
/// pernah online, aplikasi di bawahnya tidak pernah dibongkar: layar luring
/// hanya ditumpuk di atasnya. Begitu internet kembali, kasir berada di
/// layar yang sama dengan isian yang sama.
class ConnectionGate extends ConsumerStatefulWidget {
  const ConnectionGate({
    super.key,
    required this.child,
    this.requireInternet = true,
  });

  final Widget child;
  final bool requireInternet;

  @override
  ConsumerState<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends ConsumerState<ConnectionGate> {
  bool _wasOnline = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.requireInternet) return widget.child;

    final status = ref.watch(connectionProvider);
    if (status == NetworkStatus.online) _wasOnline = true;

    // Pembukaan pertama: belum ada yang bisa hilang, jadi aplikasi baru
    // digambar setelah koneksi terbukti ada.
    if (!_wasOnline) {
      return status == NetworkStatus.offline
          ? const OfflineScreen()
          : const _CheckingScreen();
    }

    return Stack(
      children: [
        // Selalu di posisi pertama supaya elemennya tidak pernah diganti.
        widget.child,
        if (status == NetworkStatus.offline)
          const Positioned.fill(child: OfflineScreen()),
      ],
    );
  }
}

class _CheckingScreen extends StatelessWidget {
  const _CheckingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Memeriksa koneksi internet...'),
            ],
          ),
        ),
      );
}

class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  bool _checking = false;

  /// Pemeriksaan ulang tidak lagi mengubah status menjadi "memeriksa",
  /// jadi tanda sibuknya dipegang tombol ini sendiri.
  Future<void> _retry() async {
    setState(() => _checking = true);
    await ref.read(connectionProvider.notifier).check();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wifi_off_rounded,
                        size: 44, color: scheme.onErrorContainer),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Tidak ada koneksi internet',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Aplikasi membutuhkan internet untuk berjalan. '
                    'Hubungkan perangkat ke Wi-Fi atau nyalakan data seluler, '
                    'lalu coba lagi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Data transaksi Anda tersimpan aman di perangkat dan '
                    'tidak ada yang hilang.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _retry,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_checking ? 'Memeriksa...' : 'Coba lagi'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aplikasi memeriksa koneksi ulang otomatis setiap 10 detik.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilah tipis yang muncul di atas layar saat koneksi putus di tengah kerja.
/// Dipakai bila gerbang keras dimatikan.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    if (status != NetworkStatus.offline) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Internet terputus',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => ref.read(connectionProvider.notifier).check(),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
