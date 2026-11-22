import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionState { checking, online, offline }

/// Memeriksa koneksi internet sungguhan, bukan sekadar status antarmuka.
///
/// `connectivity_plus` hanya melaporkan apakah Wi-Fi atau data seluler aktif.
/// Perangkat bisa tersambung ke Wi-Fi hotspot yang sama sekali tidak punya
/// jalan keluar ke internet, dan kasir akan mengira aplikasi rusak. Karena itu
/// setiap perubahan status disusul satu pemeriksaan DNS singkat.
class ConnectionController extends StateNotifier<ConnectionState> {
  ConnectionController() : super(ConnectionState.checking) {
    _subscription = Connectivity().onConnectivityChanged.listen((_) {
      check();
    });
    check();
  }

  StreamSubscription<Object?>? _subscription;
  Timer? _retryTimer;

  static const _probeHosts = ['google.com', 'cloudflare.com'];

  Future<void> check() async {
    state = ConnectionState.checking;

    final results = await Connectivity().checkConnectivity();
    final hasInterface =
        results.any((r) => r != ConnectivityResult.none);

    if (!hasInterface) {
      _goOffline();
      return;
    }

    if (await _canReachInternet()) {
      _retryTimer?.cancel();
      state = ConnectionState.online;
    } else {
      _goOffline();
    }
  }

  void _goOffline() {
    state = ConnectionState.offline;

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
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionController, ConnectionState>(
  (ref) => ConnectionController(),
);

/// Pembungkus yang menutup seluruh aplikasi saat internet terputus.
///
/// Aplikasi ini dijalankan dengan [requireInternet] bernilai false, lihat
/// app.dart: konter tetap melayani pelanggan walau jaringan mati, dan
/// seluruh lapisan datanya memang sanggup bekerja tanpa internet.
///
/// Gerbangnya tidak dihapus karena ia keputusan bisnis, bukan keterbatasan
/// teknis: bila suatu hari aplikasi harus memaksa pengguna daring, satu
/// baris di app.dart cukup untuk menghidupkannya kembali.
class ConnectionGate extends ConsumerWidget {
  const ConnectionGate({
    super.key,
    required this.child,
    this.requireInternet = true,
  });

  final Widget child;
  final bool requireInternet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!requireInternet) return child;

    final status = ref.watch(connectionProvider);

    return switch (status) {
      ConnectionState.online => child,
      ConnectionState.checking => const _CheckingScreen(),
      ConnectionState.offline => const OfflineScreen(),
    };
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

class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      onPressed: () =>
                          ref.read(connectionProvider.notifier).check(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
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
    if (status != ConnectionState.offline) return const SizedBox.shrink();

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
