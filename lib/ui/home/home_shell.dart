import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_list_screen.dart';
import '../reports/report_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_screen.dart';

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

    // Interstitial ditayangkan SEKALI per sesi, di titik transisi setelah
    // kasir masuk, dan tidak pernah di tengah transaksi. Kebijakan AdMob
    // melarang interstitial yang terpicu setelah setiap aksi pengguna.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adServiceProvider).maybeShowSessionInterstitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink();

    final pages = const [
      DashboardScreen(),
      OrderListScreen(),
      ReportScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const NewOrderScreen()),
                );
                if (created == true) ref.refreshOrderData();
              },
              icon: const Icon(Icons.add),
              label: const Text('Order Baru'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 68,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Order',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
