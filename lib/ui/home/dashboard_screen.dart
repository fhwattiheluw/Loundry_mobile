import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../services/ads/ad_service.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/stat_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final summary = ref.watch(revenueSummaryProvider);
    final stale = ref.watch(staleOrdersProvider);
    final ads = ref.watch(adServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatLongDate(DateTime.now()),
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            Text('Halo, ${user?.name ?? ''}',
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refreshOrderData(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Ringkasan hari ini selalu memakai rentang Hari ini, apa pun
            // rentang yang sedang dipilih di layar Laporan.
            summary.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: '$e'),
              data: (data) => Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Uang masuk',
                          value: formatRupiah(data.cashIn),
                          icon: Icons.payments_outlined,
                          highlight: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'Order',
                          value: '${data.orderCount}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Piutang baru',
                          value: formatRupiah(data.newReceivable),
                          icon: Icons.schedule_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'Rata-rata nota',
                          value: formatRupiah(data.averageOrderValue),
                          icon: Icons.calculate_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const _SectionTitle('Perlu tindakan'),
            const SizedBox(height: 8),

            stale.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: '$e'),
              data: (orders) {
                if (orders.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline,
                          color: Color(0xFF2E7D32)),
                      title: Text('Tidak ada cucian yang menumpuk'),
                      subtitle:
                          Text('Semua cucian selesai sudah diambil tepat waktu.'),
                    ),
                  );
                }

                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFEF6C00)),
                        title: Text(
                            '${orders.length} cucian selesai belum diambil'),
                        subtitle: const Text(
                            'Kirim pengingat lewat WhatsApp dari detail order.'),
                      ),
                      const Divider(height: 1),
                      ...orders.take(5).map(
                            (order) => ListTile(
                              dense: true,
                              title: Text(
                                  '${order.orderNo}  ${order.customerName}'),
                              subtitle: Text(
                                'Selesai ${relativeDays(order.estimatedAt, DateTime.now())}'
                                '${order.remaining > 0 ? '  ·  sisa ${formatRupiah(order.remaining)}' : ''}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderDetailScreen(orderId: order.id!),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            const _SectionTitle('Pintasan'),
            const SizedBox(height: 8),

            Card(
              child: Column(
                children: [
                  _shortcut(
                    context,
                    ref,
                    icon: Icons.local_laundry_service_outlined,
                    title: 'Sedang diproses',
                    statuses: const [LaundryStatus.diproses],
                  ),
                  const Divider(height: 1),
                  _shortcut(
                    context,
                    ref,
                    icon: Icons.inventory_2_outlined,
                    title: 'Siap diambil',
                    statuses: const [LaundryStatus.selesai],
                  ),
                  const Divider(height: 1),
                  _shortcut(
                    context,
                    ref,
                    icon: Icons.money_off_csred_outlined,
                    title: 'Belum lunas',
                    statuses: const [],
                    unpaidOnly: true,
                  ),
                ],
              ),
            ),

            SafeBannerAd(enabled: ads.enabled),
          ],
        ),
      ),
    );
  }

  Widget _shortcut(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required List<LaundryStatus> statuses,
    bool unpaidOnly = false,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        ref.read(orderFilterProvider.notifier).state = OrderFilter(
          statuses: statuses,
          unpaidOnly: unpaidOnly,
        );
        // Daftar order ada di tab kedua. Pemberitahuan singkat lebih jujur
        // daripada memindahkan tab tanpa penjelasan.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Filter "$title" dipasang. Buka tab Order.'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Data gagal dimuat'),
          subtitle: Text(message),
        ),
      );
}
