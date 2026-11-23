import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system.dart';
import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/layout.dart';
import '../widgets/states.dart';
import '../../core/friendly_error.dart';

/// Daftar piutang, diurutkan dari yang paling lama.
/// Ini layar yang membuat uang tidak hilang diam-diam.
class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(receivablesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Piutang')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(receivablesProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_outlined,
              title: 'Tidak ada piutang',
              message: 'Semua order sudah lunas. Kerja bagus!',
              tone: EmptyTone.good,
            );
          }

          final total = rows.fold(0, (sum, r) => sum + r.remaining);

          final theme = Theme.of(context);
          final bad = context.status.belumLunas;

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(
                  context.screenPadding,
                  AppSpacing.sm,
                  context.screenPadding,
                  AppSpacing.sm,
                ),
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadow.soft(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total piutang belum tertagih',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatRupiah(total),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 34,
                        ),
                      ),
                    ),
                    Text(
                      '${rows.length} order',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    context.screenPadding,
                    AppSpacing.sm,
                    context.screenPadding,
                    AppSpacing.xxxl,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final old = row.ageInDays >= 14;

                    return Card(
                      child: ListTile(
                        leading: IconBadge(
                          old
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_outlined,
                          color: old ? bad : context.status.diterima,
                        ),
                        title: Text(row.customerName,
                            style: theme.textTheme.titleMedium),
                        subtitle: Text(
                          '${row.orderNo} · ${prettyPhone(row.customerPhone)}\n'
                          'Dibuat ${formatDate(row.createdAt)} · ${row.ageInDays} hari lalu',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatRupiah(row.remaining),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: old ? bad : null,
                              ),
                            ),
                            if (row.paid > 0)
                              Text('dari ${formatRupiah(row.total)}',
                                  style: theme.textTheme.bodySmall),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderDetailScreen(orderId: row.orderId),
                            ),
                          );
                          ref.refreshOrderData();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
