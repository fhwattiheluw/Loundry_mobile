import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../services/ads/ad_service.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/layout.dart';
import '../widgets/states.dart';
import '../widgets/stat_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final summary = ref.watch(revenueSummaryProvider);
    final stale = ref.watch(staleOrdersProvider);
    final ads = ref.watch(adServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: context.screenPadding,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatLongDate(DateTime.now()),
              style: theme.textTheme.bodySmall,
            ),
            Text('Halo, ${user?.name ?? ''}', style: theme.textTheme.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
          SizedBox(width: context.screenPadding - AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refreshOrderData(),
        child: ContentWidth(
          maxWidth: 900,
          child: ListView(
            padding: screenPadding(context, bottom: 72),
            children: [
              summary.when(
                loading: () => const StatGrid(
                  children: [
                    _StatSkeleton(),
                    _StatSkeleton(),
                    _StatSkeleton(),
                    _StatSkeleton(),
                  ],
                ),
                error: (e, _) => ErrorState(
                  message: '$e',
                  onRetry: () => ref.refreshOrderData(),
                ),
                data: (data) => StatGrid(
                  children: [
                    StatTile(
                      label: 'Uang masuk hari ini',
                      value: formatRupiah(data.cashIn),
                      icon: Icons.payments_outlined,
                      highlight: true,
                    ),
                    StatTile(
                      label: 'Order',
                      value: '${data.orderCount}',
                      icon: Icons.receipt_long_outlined,
                    ),
                    StatTile(
                      label: 'Piutang baru',
                      value: formatRupiah(data.newReceivable),
                      icon: Icons.schedule_outlined,
                    ),
                    StatTile(
                      label: 'Rata-rata nota',
                      value: formatRupiah(data.averageOrderValue),
                      icon: Icons.calculate_outlined,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader('Perlu tindakan'),

              stale.when(
                loading: () => const LoadingState(height: 120),
                error: (e, _) => ErrorState(
                  message: '$e',
                  onRetry: () => ref.refreshOrderData(),
                ),
                data: (orders) => orders.isEmpty
                    ? Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.check_circle_outline,
                            color: context.status.selesai,
                          ),
                          title: const Text('Tidak ada cucian yang menumpuk'),
                          subtitle: const Text(
                            'Semua cucian selesai sudah diambil tepat waktu.',
                          ),
                        ),
                      )
                    : _StaleOrders(orders: orders),
              ),

              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader('Pintasan'),
              _Shortcuts(onPick: (filter, label) {
                ref.read(orderFilterProvider.notifier).state = filter;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Filter "$label" dipasang. Buka tab Order.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }),

              SafeBannerAd(enabled: ads.enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: 12, width: 90),
              SizedBox(height: AppSpacing.md),
              Skeleton(height: 24, width: 120),
            ],
          ),
        ),
      );
}

class _StaleOrders extends ConsumerWidget {
  const _StaleOrders({required this.orders});

  final List<LaundryOrder> orders;

  /// Pengingat boleh dikirim berkali-kali selama cucian belum diambil,
  /// jadi aturan anti-kirim-ganda sengaja dilewati di sini.
  Future<void> _remind(
    BuildContext context,
    WidgetRef ref,
    LaundryOrder order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref.read(notificationServiceProvider).notify(
          order,
          NotificationTrigger.pengingatAmbil,
          force: true,
        );

    if (!result.sent) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.warning_amber_rounded,
              color: context.status.diambil,
            ),
            title: Text('${orders.length} cucian selesai belum diambil'),
            subtitle: const Text('Ketuk ikon pesan untuk mengingatkan.'),
          ),
          const Divider(),
          for (final order in orders.take(5))
            ListTile(
              title: Text(
                '${order.orderNo}  ${order.customerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'Selesai ${relativeDays(order.estimatedAt, DateTime.now())}'
                '${order.remaining > 0 ? '  ·  sisa ${formatRupiah(order.remaining)}' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (order.customerPhone.isNotEmpty)
                    IconButton(
                      tooltip: 'Kirim pengingat WhatsApp',
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () => _remind(context, ref, order),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(orderId: order.id!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.onPick});

  final void Function(OrderFilter filter, String label) onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.local_laundry_service_outlined),
            title: const Text('Sedang diproses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPick(
              const OrderFilter(statuses: [LaundryStatus.diproses]),
              'Sedang diproses',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Siap diambil'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPick(
              const OrderFilter(statuses: [LaundryStatus.selesai]),
              'Siap diambil',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.money_off_csred_outlined),
            title: const Text('Belum lunas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPick(
              const OrderFilter(unpaidOnly: true),
              'Belum lunas',
            ),
          ),
        ],
      ),
    );
  }
}
