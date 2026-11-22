import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../services/connectivity/connection_guard.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_list_screen.dart';
import '../reports/report_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_screen.dart';

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _Destination(Icons.home_outlined, Icons.home, 'Beranda'),
  _Destination(Icons.receipt_long_outlined, Icons.receipt_long, 'Order'),
  _Destination(Icons.bar_chart_outlined, Icons.bar_chart, 'Laporan'),
  _Destination(Icons.settings_outlined, Icons.settings, 'Pengaturan'),
];

/// Rangka aplikasi yang menyesuaikan lebar layar.
///
/// Di HP, navigasi di bawah supaya terjangkau ibu jari. Di tablet, navigasi
/// pindah ke rel samping: ibu jari tidak sampai ke dasar layar tablet, dan
/// ruang mendatar yang luas lebih baik dipakai untuk isi.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Interstitial ditayangkan SEKALI per sesi, di titik transisi setelah
      // kasir masuk, dan tidak pernah di tengah transaksi. Kebijakan AdMob
      // melarang interstitial yang terpicu setelah setiap aksi pengguna.
      ref.read(adServiceProvider).maybeShowSessionInterstitial();

      // Backup otomatis maksimal sekali sehari. Data aplikasi ini hanya ada
      // di satu perangkat, jadi salinan harian adalah pengaman paling murah.
      ref.read(backupServiceProvider).autoBackupIfDue();

      // Pesan yang gagal kirim dan sudah waktunya dicoba lagi (FR-69).
      // Hanya berjalan di mode API; mode manual butuh kasir menekan kirim.
      ref.read(notificationServiceProvider).processQueue().then((sent) {
        if (sent > 0) ref.invalidate(pendingNotificationsProvider);
      });
    });
  }

  Future<void> _newOrder() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewOrderScreen()),
    );
    if (created == true) ref.refreshOrderData();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink();

    final wide = context.isWide;

    const pages = [
      DashboardScreen(),
      OrderListScreen(),
      ReportScreen(),
      SettingsScreen(),
    ];

    // Tanpa internet aplikasi tetap jalan penuh, tapi pesan WhatsApp
    // mengantre dan iklan tidak dimuat. Kasir berhak tahu itu, tanpa
    // dihalangi bekerja.
    //
    // Garis itu sudah memakai ruang status bar. Layar di bawahnya tidak
    // boleh menambah jarak status bar lagi, kalau tidak muncul celah kosong.
    final offline = ref.watch(connectionProvider) == NetworkStatus.offline;
    final stack = IndexedStack(index: _index, children: pages);
    final body = Column(
      children: [
        const _OfflineStrip(),
        Expanded(
          child: offline
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: stack,
                )
              : stack,
        ),
      ],
    );
    final showFab = _index <= 1;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              // Tombol order baru ikut di rel, supaya tetap terjangkau
              // tanpa melayang menutupi isi tabel.
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: showFab
                    ? FloatingActionButton(
                        onPressed: _newOrder,
                        tooltip: 'Order baru',
                        child: const Icon(Icons.add),
                      )
                    : const SizedBox(height: AppTouch.comfortable),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _newOrder,
              icon: const Icon(Icons.add),
              label: const Text('Order Baru'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Garis tipis pemberitahuan saat jaringan mati. Sengaja setipis mungkin:
/// ia memberi tahu, bukan menghalangi.
class _OfflineStrip extends ConsumerWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    if (status != NetworkStatus.offline) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tanpa internet. Transaksi tetap tersimpan, pesan WhatsApp '
                  'menunggu giliran kirim.',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
