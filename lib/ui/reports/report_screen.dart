import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system.dart';
import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/report_repository.dart';
import '../../services/ads/ad_service.dart';
import '../widgets/layout.dart';
import '../widgets/stat_tile.dart';
import 'receivables_screen.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final range = ref.watch(reportRangeProvider);
    final summary = ref.watch(revenueSummaryProvider);

    // Kasir hanya melihat shift sendiri. Laporan keseluruhan milik Owner.
    if (user != null && !user.isOwner) {
      return const _CashierNotice();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Pendapatan'),
        actions: [
          IconButton(
            tooltip: 'Piutang',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceivablesScreen()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ekspor',
            icon: const Icon(Icons.ios_share),
            onSelected: (value) => switch (value) {
              'print' => _printReport(context, ref),
              'pdf' => _export(context, ref, asPdf: true),
              _ => _export(context, ref, asPdf: false),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'print',
                child: ListTile(
                  leading: Icon(Icons.print_outlined),
                  title: Text('Cetak di printer struk'),
                  subtitle: Text('Lewat printer Bluetooth'),
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Ekspor CSV'),
                  subtitle: Text('Buka di Excel'),
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Ekspor PDF'),
                  subtitle: Text('Siap dicetak atau dikirim'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refreshOrderData(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final preset in [
                    ReportRange.today(),
                    ReportRange.thisWeek(),
                    ReportRange.thisMonth(),
                    ReportRange.lastMonth(),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(preset.label),
                        selected: range.label == preset.label,
                        onSelected: (_) => ref
                            .read(reportRangeProvider.notifier)
                            .state = preset,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: const Text('Pilih tanggal'),
                      onPressed: () => _pickRange(context, ref),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            summary.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Gagal memuat: $e'),
              data: (data) => Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Pendapatan (uang diterima)',
                          value: formatRupiah(data.cashIn),
                          icon: Icons.trending_up,
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
                          label: 'Jumlah order',
                          value: '${data.orderCount}',
                          icon: Icons.receipt_long_outlined,
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
                  // Kotak yang isinya nol hanya memakan tempat untuk
                  // mengatakan tidak ada apa-apa. Baris ini hilang sama
                  // sekali bila tidak ada diskon maupun refund.
                  if (data.discountTotal > 0 || data.refundTotal > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (data.discountTotal > 0)
                      Expanded(
                        child: StatTile(
                          label: 'Diskon diberikan',
                          value: formatRupiah(data.discountTotal),
                          icon: Icons.discount_outlined,
                        ),
                      ),
                      if (data.discountTotal > 0 && data.refundTotal > 0)
                        const SizedBox(width: 12),
                      if (data.refundTotal > 0)
                      Expanded(
                        child: StatTile(
                          label: 'Refund',
                          value: formatRupiah(data.refundTotal),
                          icon: Icons.undo,
                        ),
                      ),
                    ],
                  ),
                  ],
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const IconBadge(Icons.info_outline, tone: 1),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Nilai order periode ini ${formatRupiah(data.grossOrderValue)}. '
                              'Selisihnya dengan pendapatan adalah piutang yang belum masuk.',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const _Heading('Dibanding periode sebelumnya'),
            const SizedBox(height: 8),
            const _ComparisonCard(),

            const SizedBox(height: 20),
            const _Heading('Tren harian'),
            const SizedBox(height: 8),
            const _RevenueChart(),

            const SizedBox(height: 20),
            const _Heading('Per layanan'),
            const SizedBox(height: 8),
            _AmountList(provider: revenueByServiceProvider, showQty: true),

            const SizedBox(height: 20),
            const _Heading('Per metode bayar'),
            const SizedBox(height: 8),
            _AmountList(provider: revenueByMethodProvider),

            const SizedBox(height: 20),
            const _Heading('Per kasir'),
            const SizedBox(height: 8),
            _AmountList(provider: revenueByCashierProvider),

            const SizedBox(height: 20),
            const _Heading('Pelanggan teratas'),
            const SizedBox(height: 8),
            _AmountList(provider: topCustomersProvider),

          ],
        ),
      ),
    );
  }

  /// Ekspor laporan.
  ///
  /// CSV selalu gratis supaya pemilik tidak pernah terhalang mengambil
  /// datanya sendiri. PDF ditawarkan lewat rewarded ad yang benar-benar
  /// bisa ditolak, sesuai format iklan yang memang diizinkan AdMob.
  /// Mencetak laporan periode yang sedang dilihat ke printer struk.
  ///
  /// Angka-angkanya dibaca ulang dari provider yang sama dengan yang
  /// menggambar layar, bukan dari salinan, supaya kertas dan layar tidak
  /// pernah menyebut dua angka berbeda.
  Future<void> _printReport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final range = ref.read(reportRangeProvider);

    messenger.showSnackBar(
      const SnackBar(content: Text('Menyiapkan laporan...')),
    );

    try {
      final summary = await ref.read(revenueSummaryProvider.future);
      final byMethod = await ref.read(revenueByMethodProvider.future);
      final byService = await ref.read(revenueByServiceProvider.future);

      final bytes = await ref.read(receiptBuilderProvider).buildRevenueReport(
            rangeLabel: range.label,
            from: range.from,
            to: range.to,
            summary: summary,
            byMethod: byMethod,
            byService: byService,
            printedBy: ref.read(currentUserProvider).name,
          );

      final result = await ref.read(printerProvider).printBytes(bytes, copies: 1);

      messenger.showSnackBar(
        SnackBar(
          content: Text(result.success
              ? 'Laporan tercetak.'
              : 'Gagal mencetak. ${result.message}'),
        ),
      );

      // Laporan sudah di tangan pemilik. Tidak ada pekerjaan yang terpotong
      // di sini, dan jeda minimum di AdService menahan iklan kedua bila ia
      // baru saja menutup shift.
      unawaited(
          ref.read(adServiceProvider).showInterstitialAt('cetak laporan'));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan laporan: $e')),
      );
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool asPdf,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final range = ref.read(reportRangeProvider);
    final settings = ref.read(settingsRepoProvider);
    final ads = ref.read(adServiceProvider);

    if (asPdf && ads.enabled && ads.rewardedReady) {
      final accepted = await offerRewardedAd(
        context,
        title: 'Ekspor PDF',
        description:
            'Tonton satu iklan singkat untuk membuat laporan PDF. '
            'Ekspor CSV dengan data yang sama selalu tersedia tanpa iklan.',
        rewardLabel: 'Hadiah: laporan PDF siap cetak',
      );

      if (!accepted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Dibatalkan. Ekspor CSV tersedia tanpa iklan.'),
          ),
        );
        return;
      }

      final watched = await ads.showRewarded();
      if (!watched) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Iklan tidak selesai ditonton. Coba lagi, '
                'atau pakai ekspor CSV.'),
          ),
        );
        return;
      }
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Menyiapkan laporan...')),
    );

    final summary = await ref.read(revenueSummaryProvider.future);
    final byService = await ref.read(revenueByServiceProvider.future);
    final byMethod = await ref.read(revenueByMethodProvider.future);
    final exporter = ref.read(exportServiceProvider);

    final result = asPdf
        ? await exporter.exportPdf(
            from: range.from,
            to: range.to,
            businessName: settings.get(SettingsKeys.businessName),
            businessAddress: settings.get(SettingsKeys.businessAddress),
            summary: summary,
            byService: byService,
            byMethod: byMethod,
          )
        : await exporter.exportCsv(
            from: range.from,
            to: range.to,
            businessName: settings.get(SettingsKeys.businessName),
            summary: summary,
            daily: await ref.read(dailyRevenueProvider.future),
            byService: byService,
            byMethod: byMethod,
          );

    if (!result.success) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );

    if (picked == null) return;

    ref.read(reportRangeProvider.notifier).state = ReportRange(
      picked.start,
      picked.end,
      '${formatDate(picked.start)} - ${formatDate(picked.end)}',
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Perbandingan dengan periode sebelumnya yang panjangnya sama (FR-108).
class _ComparisonCard extends ConsumerWidget {
  const _ComparisonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(revenueSummaryProvider);
    final before = ref.watch(previousPeriodProvider);

    if (now.isLoading || before.isLoading) {
      return const Card(
        child: SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final current = now.valueOrNull;
    final previous = before.valueOrNull;

    if (current == null || previous == null) {
      return const Card(
        child: ListTile(title: Text('Data pembanding belum tersedia')),
      );
    }

    return Card(
      child: Column(
        children: [
          _CompareRow(
            label: 'Pendapatan',
            current: current.cashIn,
            previous: previous.cashIn,
          ),
          const Divider(height: 1),
          _CompareRow(
            label: 'Jumlah order',
            current: current.orderCount,
            previous: previous.orderCount,
            isMoney: false,
          ),
          const Divider(height: 1),
          _CompareRow(
            label: 'Rata-rata nota',
            current: current.averageOrderValue,
            previous: previous.averageOrderValue,
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.current,
    required this.previous,
    this.isMoney = true,
  });

  final String label;
  final int current;
  final int previous;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final diff = current - previous;

    // Persentase tidak bisa dihitung dari nol, dan menampilkan "naik 100%"
    // dari nol hanya menyesatkan.
    final percent = previous == 0 ? null : (diff / previous * 100).round();

    final naik = diff > 0;
    final color = diff == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : naik
            ? context.status.lunas
            : context.status.belumLunas;

    String show(int value) =>
        isMoney ? formatRupiah(value) : value.toString();

    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text('Sebelumnya ${show(previous)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(show(current),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                diff == 0
                    ? Icons.remove
                    : naik
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                size: 13,
                color: color,
              ),
              Text(
                percent == null
                    ? show(diff.abs())
                    : '${percent.abs()}%',
                style: TextStyle(
                    fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends ConsumerWidget {
  const _RevenueChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dailyRevenueProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 20, 12),
        child: SizedBox(
          height: 220,
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (days) {
              if (days.isEmpty) {
                return const Center(child: Text('Belum ada data'));
              }

              if (days.every((d) => d.amount == 0)) {
                return Center(
                  child: Text('Belum ada pemasukan di periode ini',
                      style: Theme.of(context).textTheme.bodySmall),
                );
              }

              final maxY = days
                  .map((d) => d.amount)
                  .reduce((a, b) => a > b ? a : b)
                  .toDouble();

              return LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY * 1.2,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY <= 0 ? 1 : maxY / 2,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: maxY <= 0 ? 1 : maxY / 2,
                        getTitlesWidget: (value, meta) => Text(
                          _short(value.toInt()),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (days.length / 5).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              formatDayMonth(days[i].date),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < days.length; i++)
                          FlSpot(i.toDouble(), days[i].amount.toDouble()),
                      ],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      barWidth: 3,
                      color: scheme.primary,
                      dotData: FlDotData(show: days.length <= 14),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.primary.withValues(alpha: 0.28),
                            scheme.primary.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 1.250.000 menjadi "1,2jt" supaya sumbu tidak penuh angka.
  static String _short(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')}jt';
    }
    if (value >= 1000) return '${value ~/ 1000}rb';
    return '$value';
  }
}

class _AmountList extends ConsumerWidget {
  const _AmountList({required this.provider, this.showQty = false});

  final ProviderListenable<AsyncValue<List<NamedAmount>>> provider;
  final bool showQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(provider);

    return Card(
      child: data.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => ListTile(title: Text('Gagal memuat: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const ListTile(title: Text('Belum ada data'));
          }

          final total = rows.fold(0, (sum, r) => sum + r.amount);

          return Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: IconBadge.tones[i % IconBadge.tones.length]
                        .withValues(alpha: 0.14),
                    foregroundColor:
                        IconBadge.tones[i % IconBadge.tones.length],
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(rows[i].name),
                  subtitle: Text(
                    showQty
                        ? '${rows[i].count} order · ${formatQty(rows[i].qty)} satuan'
                        : '${rows[i].count} transaksi',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatRupiah(rows[i].amount),
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      if (total > 0)
                        Text(
                          '${(rows[i].amount / total * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CashierNotice extends StatelessWidget {
  const _CashierNotice();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Laporan')),
        body: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(height: 16),
                Text(
                  'Laporan pendapatan hanya bisa dibuka Owner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
                SizedBox(height: 8),
                Text(
                  'Rekap shift Anda sendiri ada di menu Pengaturan.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
}
