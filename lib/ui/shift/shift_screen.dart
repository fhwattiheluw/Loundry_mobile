import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system.dart';
import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../domain/models/models.dart';
import '../widgets/layout.dart';
import '../widgets/stat_tile.dart';
import '../../core/friendly_error.dart';
import '../widgets/states.dart';

/// Buka dan tutup shift kasir.
///
/// Angka "kas seharusnya" dihitung aplikasi, "kas fisik" dihitung manusia.
/// Selisih keduanya yang memberi tahu pemilik ada yang perlu ditanyakan.
class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(currentShiftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shift Kasir')),
      body: ContentWidth(
        child: shift.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(currentShiftProvider),
          ),
          data: (open) =>
              open == null ? const _OpenShiftForm() : _OpenShiftView(shift: open),
        ),
      ),
    );
  }
}

class _OpenShiftForm extends ConsumerStatefulWidget {
  const _OpenShiftForm();

  @override
  ConsumerState<_OpenShiftForm> createState() => _OpenShiftFormState();
}

class _OpenShiftFormState extends ConsumerState<_OpenShiftForm> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _saving = true);

    final user = ref.read(currentUserProvider);
    await ref.read(shiftRepoProvider).open(
          userId: user.id!,
          openingCash: parseRupiah(_controller.text),
        );

    ref.invalidate(currentShiftProvider);
    ref.invalidate(shiftTotalsProvider);

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: AppGradient.brand(context),
              shape: BoxShape.circle,
              boxShadow: AppShadow.soft(context),
            ),
            child: const Icon(
              Icons.point_of_sale_outlined,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Belum ada shift yang dibuka',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Hitung uang yang ada di laci sekarang, lalu masukkan jumlahnya. '
          'Angka ini yang dipakai menghitung selisih saat tutup shift.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: rupiahInputFormatters,
          decoration: const InputDecoration(
            labelText: 'Kas awal di laci',
            prefixText: 'Rp ',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _open,
          icon: const Icon(Icons.play_arrow),
          label: Text(_saving ? 'Membuka...' : 'Buka shift'),
        ),
      ],
    );
  }
}

class _OpenShiftView extends ConsumerWidget {
  const _OpenShiftView({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(shiftTotalsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(shiftTotalsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: IconBadge(
                Icons.play_circle_outline,
                color: context.status.selesai,
              ),
              title: const Text('Shift berjalan'),
              subtitle: Text('Dibuka ${formatDateTime(shift.openedAt)}'),
            ),
          ),
          const SizedBox(height: 16),
          totals.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Ringkasan belum bisa dimuat. ${friendlyError(e)}'),
            data: (data) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Uang masuk shift ini',
                        value: formatRupiah(data.cashIn),
                        icon: Icons.payments_outlined,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Order dibuat',
                        value: '${data.orderCount}',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        label: 'Transaksi bayar',
                        value: '${data.paymentCount}',
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Per metode bayar',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                      if (data.byMethod.isEmpty)
                        const ListTile(
                          dense: true,
                          title: Text('Belum ada pembayaran di shift ini'),
                        )
                      else
                        for (final entry in data.byMethod.entries)
                          ListTile(
                            dense: true,
                            title: Text(entry.key),
                            trailing: Text(
                              formatRupiah(entry.value),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: const Text('Kas awal'),
                        trailing: Text(formatRupiah(shift.openingCash)),
                      ),
                      ListTile(
                        dense: true,
                        title: const Text('Kas seharusnya di laci'),
                        subtitle: const Text('Kas awal + pembayaran tunai'),
                        trailing: Text(
                          formatRupiah(shift.openingCash + data.cashOnly),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _closeShift(context, ref),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Tutup shift'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeShift(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(shiftRepoProvider);
    final expected = await repo.expectedCash(shift);

    if (!context.mounted) return;

    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final counted = parseRupiah(controller.text);
          final difference = counted - expected;

          return AlertDialog(
            title: const Text('Tutup shift'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kas seharusnya: ${formatRupiah(expected)}'),
                const SizedBox(height: 4),
                Text(
                  'Hitung uang fisik di laci, lalu masukkan jumlahnya.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: rupiahInputFormatters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Kas fisik',
                    prefixText: 'Rp ',
                  ),
                ),
                if (controller.text.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (difference == 0
                              ? context.status.lunas
                              : context.status.diambil)
                          .withValues(alpha: context.status.onStatusTint),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      difference == 0
                          ? 'Kas cocok'
                          : difference > 0
                              ? 'Lebih ${formatRupiah(difference)}'
                              : 'Kurang ${formatRupiah(-difference)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: controller.text.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Tutup & cetak'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);
    final totals = await repo.totalsOf(shift);

    final closed = await repo.close(
      shift: shift,
      closingCash: parseRupiah(controller.text),
    );

    final bytes = await ref.read(receiptBuilderProvider).buildShiftReport(
          closed,
          cashierName: user.name,
          totals: totals,
        );

    final result = await ref.read(printerProvider).printBytes(bytes, copies: 1);

    ref.invalidate(currentShiftProvider);
    ref.invalidate(shiftTotalsProvider);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Shift ditutup dan laporan dicetak.'
            : 'Shift ditutup. Laporan gagal dicetak: ${result.message}'),
      ),
    );

    // Shift sudah tertutup dan laporannya tercetak: kasir berhenti bekerja
    // di titik ini. Iklan di sini tidak menyela apa pun. Pemanggilan ini
    // tidak ditunggu, jadi tidak ada yang tertahan bila iklannya lambat.
    unawaited(ref.read(adServiceProvider).showInterstitialAt('tutup shift'));
  }
}

/// Riwayat shift yang sudah ditutup. Hanya untuk Owner.
class ShiftHistoryScreen extends ConsumerWidget {
  const ShiftHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Shift')),
      body: ContentWidth(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: ref.watch(shiftRepoProvider).history(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const Center(child: Text('Belum ada shift yang ditutup.'));
            }

            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = rows[i];
                final shift = Shift.fromMap(row);
                final difference = shift.difference ?? 0;

                return ListTile(
                  title: Text(row['user_name'] as String),
                  subtitle: Text(
                    '${formatDateTime(shift.openedAt)}\n'
                    'Kas seharusnya ${formatRupiah(shift.expectedCash ?? 0)} · '
                    'fisik ${formatRupiah(shift.closingCash ?? 0)}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    difference == 0 ? 'Cocok' : formatRupiah(difference),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: difference == 0
                          ? context.status.lunas
                          : context.status.belumLunas,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
