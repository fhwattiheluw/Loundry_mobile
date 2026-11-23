import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../services/ads/ad_service.dart';
import '../../services/backup/backup_reminder.dart';
import '../backup/backup_wizard_screen.dart';
import '../customers/customer_screen.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_detail_screen.dart';
import '../orders/scan_order_screen.dart';
import '../reports/receivables_screen.dart';
import '../widgets/layout.dart';
import '../widgets/states.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _openNewOrder(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewOrderScreen()),
    );
    if (created == true) ref.refreshOrderData();
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final summary = ref.watch(revenueSummaryProvider);
    final stale = ref.watch(staleOrdersProvider);
    final backup = ref.watch(backupStatusProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.refreshOrderData(),
        child: SafeArea(
          bottom: false,
          child: ContentWidth(
            maxWidth: 900,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.screenPadding,
                AppSpacing.sm,
                context.screenPadding,
                96,
              ),
              children: [
                _HeroCard(
                  name: user?.name ?? '',
                  summary: summary,
                  onSignOut: () => ref.read(sessionProvider.notifier).signOut(),
                  onRetry: () => ref.refreshOrderData(),
                ),

                const SizedBox(height: AppSpacing.xl),
                _QuickActions(
                  actions: [
                    _QuickAction(
                      icon: Icons.add_circle_outline,
                      label: 'Order\nBaru',
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () => _openNewOrder(context, ref),
                    ),
                    _QuickAction(
                      icon: Icons.qr_code_scanner,
                      label: 'Scan\nNota',
                      color: context.status.diproses,
                      onTap: () => _push(context, const ScanOrderScreen()),
                    ),
                    _QuickAction(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Piutang',
                      color: context.status.belumLunas,
                      onTap: () => _push(context, const ReceivablesScreen()),
                    ),
                    _QuickAction(
                      icon: Icons.people_alt_outlined,
                      label: 'Pelanggan',
                      color: context.status.diterima,
                      onTap: () => _push(context, const CustomerScreen()),
                    ),
                  ],
                ),

                // Muncul hanya bila backup terlambat, di atas semua hal lain:
                // kehilangan data lebih mahal daripada cucian yang telat
                // diambil, dan pemilik tidak akan mencarinya sendiri.
                if (backup.overdue) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _BackupReminderCard(
                    status: backup,
                    onBackup: () => _push(context, const BackupWizardScreen()),
                  ),
                ],

                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader('Perlu tindakan'),
                stale.when(
                  loading: () => const LoadingState(height: 120),
                  error: (e, _) => ErrorState(
                    message: '$e',
                    onRetry: () => ref.refreshOrderData(),
                  ),
                  data: (orders) => orders.isEmpty
                      ? const _AllClear()
                      : _StaleOrders(orders: orders),
                ),

                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader('Pantau cucian'),
                _StatusShortcuts(onPick: (filter, label) {
                  ref.read(orderFilterProvider.notifier).state = filter;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Filter "$label" dipasang. Buka tab Order.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }),

                // Iklan native di ujung beranda, berjarak dari kartu yang
                // bisa diketuk di atasnya supaya tidak terpencet tanpa sengaja.
                const SizedBox(height: AppSpacing.xxl),
                SafeNativeAd(enabled: ref.watch(adServiceProvider).enabled),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu utama beranda: sapaan, pendapatan hari ini, dan tiga angka
/// pendukung dalam satu bidang gradasi, supaya mata langsung tahu
/// angka mana yang paling penting.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.name,
    required this.summary,
    required this.onSignOut,
    required this.onRetry,
  });

  final String name;
  final AsyncValue<RevenueSummary> summary;
  final VoidCallback onSignOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBrand = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.75);

    return Container(
      decoration: BoxDecoration(
        gradient: AppGradient.brand(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadow.soft(context),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Image.asset('assets/brand/logo.png'),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatLongDate(DateTime.now()),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    Text(
                      'Halo, $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: onBrand),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Keluar',
                onPressed: onSignOut,
                color: onBrand,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Uang masuk hari ini',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          summary.when(
            loading: () => const _HeroLoading(),
            error: (e, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Data belum bisa dimuat',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: onBrand),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: onBrand),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRupiah(data.cashIn),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 36,
                      color: onBrand,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                    horizontal: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      _HeroStat(
                        label: 'Order',
                        value: '${data.orderCount}',
                      ),
                      _HeroDivider(),
                      _HeroStat(
                        label: 'Piutang baru',
                        value: formatRupiah(data.newReceivable),
                      ),
                      _HeroDivider(),
                      _HeroStat(
                        label: 'Rata-rata nota',
                        value: formatRupiah(data.averageOrderValue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroLoading extends StatelessWidget {
  const _HeroLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 36, width: 200),
            SizedBox(height: AppSpacing.lg),
            Skeleton(height: 52),
          ],
        ),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: Colors.white.withValues(alpha: 0.25),
      );
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Empat tombol bulat untuk pekerjaan yang paling sering dilakukan.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(a.icon, color: a.color, size: 28),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BackupReminderCard extends StatelessWidget {
  const _BackupReminderCard({required this.status, required this.onBackup});

  final BackupStatus status;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final title = status.neverBackedUp
        ? 'Data Anda belum pernah di-backup'
        : 'Backup terakhir ${status.daysSince} hari lalu';

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Kalau HP hilang atau rusak, riwayat order dan piutang '
                    'ikut hilang. Backup butuh satu menit.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: onBackup,
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Backup sekarang'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final color = context.status.selesai;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semua beres',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Tidak ada cucian selesai yang menumpuk.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                'Selesai ${relativeDays(order.finishedAt ?? order.estimatedAt, DateTime.now())}'
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

class _StatusShortcuts extends StatelessWidget {
  const _StatusShortcuts({required this.onPick});

  final void Function(OrderFilter filter, String label) onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.status;

    return Row(
      children: [
        _StatusTile(
          icon: Icons.local_laundry_service_outlined,
          label: 'Diproses',
          color: palette.diproses,
          onTap: () => onPick(
            const OrderFilter(statuses: [LaundryStatus.diproses]),
            'Sedang diproses',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _StatusTile(
          icon: Icons.inventory_2_outlined,
          label: 'Siap diambil',
          color: palette.selesai,
          onTap: () => onPick(
            const OrderFilter(statuses: [LaundryStatus.selesai]),
            'Siap diambil',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _StatusTile(
          icon: Icons.money_off_csred_outlined,
          label: 'Belum lunas',
          color: palette.belumLunas,
          onTap: () => onPick(
            const OrderFilter(unpaidOnly: true),
            'Belum lunas',
          ),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = context.status.onStatusTint;

    return Expanded(
      child: Material(
        color: color.withValues(alpha: tint),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.sm,
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
