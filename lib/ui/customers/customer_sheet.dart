import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../data/repositories/master_repository.dart';
import '../../domain/models/models.dart';
import '../orders/new_order_screen.dart';
import '../widgets/actions.dart';

/// Kartu pelanggan: riwayat singkat lalu tombolnya.
///
/// Sebelumnya mengetuk nama pelanggan langsung membuka formulir ubah data,
/// padahal yang paling sering dibutuhkan di konter adalah membuat order
/// untuk orang itu dan melihat apakah dia masih punya tagihan.
Future<void> showCustomerSheet(
  BuildContext context,
  Customer customer, {
  required VoidCallback onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerSheet(customer: customer, onEdit: onEdit),
  );
}

class _CustomerSheet extends ConsumerWidget {
  const _CustomerSheet({required this.customer, required this.onEdit});

  final Customer customer;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.status;
    final hasPhone = customer.phone.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                  foregroundColor: scheme.primary,
                  child: Text(
                    customer.name.isEmpty
                        ? '?'
                        : customer.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        hasPhone
                            ? prettyPhone(customer.phone)
                            : 'Tanpa nomor WhatsApp',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ubah data',
                  onPressed: () {
                    Navigator.pop(context);
                    onEdit();
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if ((customer.address ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(customer.address!)),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<CustomerStats>(
              future: customer.id == null
                  ? Future.value(CustomerStats.empty)
                  : ref.read(customerRepoProvider).statsFor(customer.id!),
              builder: (context, snapshot) {
                final stats = snapshot.data;

                if (stats == null) {
                  return Container(
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _stat(context, 'Order', '${stats.orderCount}'),
                            _divider(scheme),
                            _stat(context, 'Total belanja',
                                formatRupiah(stats.totalValue)),
                            _divider(scheme),
                            _stat(
                              context,
                              'Sisa tagihan',
                              formatRupiah(stats.outstanding),
                              color: stats.outstanding > 0
                                  ? palette.belumLunas
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      stats.lastOrderAt == null
                          ? 'Belum pernah order.'
                          : 'Terakhir order ${formatDate(stats.lastOrderAt!)}.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            ActionStack(
              primary: [
                AppAction(
                  label: 'Order baru untuk ${customer.name.split(' ').first}',
                  icon: Icons.add,
                  kind: ActionKind.primary,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<bool>(
                      builder: (_) => NewOrderScreen(customer: customer),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) =>
      VerticalDivider(width: 1, color: scheme.outlineVariant);

  Widget _stat(BuildContext context, String label, String value,
      {Color? color}) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
