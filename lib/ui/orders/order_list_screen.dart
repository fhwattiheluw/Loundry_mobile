import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/order_grouping.dart';
import '../../services/ads/ad_service.dart';
import '../widgets/states.dart';
import '../widgets/stat_tile.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';
import 'scan_order_screen.dart';
import 'status_confirm.dart';
import '../../core/friendly_error.dart';
import '../widgets/layout.dart';

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  final _searchController = TextEditingController();
  final _selected = <int>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilter(OrderFilter filter) {
    ref.read(orderFilterProvider.notifier).state = filter;
  }

  Future<void> _bulkChangeStatus(LaundryStatus status) async {
    final user = ref.read(currentUserProvider);

    final approved = await confirmStatusChange(
      context,
      to: status,
      subject: '${_selected.length} order terpilih',
      willNotifyCustomer: true,
      extraWarning: 'Perubahan berlaku untuk semua order yang dipilih, dan '
          'tidak bisa dibatalkan sekaligus.',
    );
    if (!approved || !mounted) return;

    await ref
        .read(orderRepoProvider)
        .changeStatusBulk(_selected.toList(), status, user: user);

    if (!mounted) return;
    final count = _selected.length;
    setState(_selected.clear);
    ref.refreshOrderData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count order diubah ke ${status.label}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(orderFilterProvider);
    final orders = ref.watch(orderListProvider);
    final ads = ref.watch(adServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: _selected.isEmpty
            ? const Text('Daftar Order')
            : Text('${_selected.length} dipilih'),
        actions: _selected.isEmpty
            ? [
                IconButton(
                  tooltip: 'Pindai QR nota',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ScanOrderScreen()),
                  ),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Tandai diproses',
                  onPressed: () => _bulkChangeStatus(LaundryStatus.diproses),
                  icon: const Icon(Icons.local_laundry_service_outlined),
                ),
                IconButton(
                  tooltip: 'Tandai selesai',
                  onPressed: () => _bulkChangeStatus(LaundryStatus.selesai),
                  icon: const Icon(Icons.check_circle_outline),
                ),
                IconButton(
                  tooltip: 'Batal pilih',
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
              ],
      ),
      body: ContentWidth(
        maxWidth: 900,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(context.screenPadding, AppSpacing.sm, context.screenPadding, 0),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari nomor nota, nama, atau nomor HP',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  suffixIcon: filter.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _setFilter(filter.copyWith(query: ''));
                          },
                        ),
                ),
                onChanged: (value) => _setFilter(filter.copyWith(query: value)),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: context.screenPadding - AppSpacing.xs),
                children: [
                  _chip(
                    'Semua',
                    selected: filter.statuses.isEmpty && !filter.unpaidOnly,
                    onTap: () => _setFilter(const OrderFilter()),
                  ),
                  for (final status in [
                    LaundryStatus.diterima,
                    LaundryStatus.diproses,
                    LaundryStatus.selesai,
                    LaundryStatus.diambil,
                  ])
                    _chip(
                      status.label,
                      selected: filter.statuses.contains(status),
                      onTap: () => _setFilter(OrderFilter(
                        statuses: [status],
                        query: filter.query,
                      )),
                    ),
                  _chip(
                    'Belum lunas',
                    selected: filter.unpaidOnly,
                    onTap: () => _setFilter(OrderFilter(
                      unpaidOnly: true,
                      query: filter.query,
                    )),
                  ),
                ],
              ),
            ),
            Expanded(
              child: orders.when(
                loading: () => ListView.separated(
                  padding: screenPadding(context, bottom: 96),
                  itemCount: 4,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, __) => const OrderCardSkeleton(),
                ),
                error: (e, _) => ErrorState(
                  message: friendlyError(e),
                  onRetry: () => ref.refreshOrderData(),
                ),
                data: (raw) {
                  final now = DateTime.now();
                  final list = raw;

                  if (list.isEmpty) {
                    final searching = filter.query.trim().isNotEmpty;
                    final filtering =
                        filter.statuses.isNotEmpty || filter.unpaidOnly;

                    // Tiga keadaan kosong yang berbeda butuh tiga jalan keluar
                    // yang berbeda: belum pernah ada order, pencarian tidak
                    // menemukan apa pun, atau filter terlalu sempit.
                    if (searching) {
                      return EmptyState(
                        icon: Icons.search_off,
                        title: 'Tidak ada yang cocok',
                        message: 'Tidak ada order untuk "${filter.query.trim()}". '
                            'Coba nama, nomor HP, atau nomor nota yang lain.',
                        action: OutlinedButton(
                          onPressed: () {
                            _searchController.clear();
                            _setFilter(filter.copyWith(query: ''));
                          },
                          child: const Text('Hapus pencarian'),
                        ),
                      );
                    }

                    if (filtering) {
                      return EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Tidak ada order di filter ini',
                        message: 'Coba filter lain, atau tampilkan semua order.',
                        action: OutlinedButton(
                          onPressed: () => _setFilter(const OrderFilter()),
                          child: const Text('Tampilkan semua'),
                        ),
                      );
                    }

                    return EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Belum ada order',
                      message: 'Order pertama Anda akan muncul di sini. '
                          'Pelanggan dan nomor nota dibuat otomatis.',
                      action: FilledButton.icon(
                        onPressed: () async {
                          final created = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                                builder: (_) => const NewOrderScreen()),
                          );
                          if (created == true) ref.refreshOrderData();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Buat order pertama'),
                      ),
                    );
                  }

                  // Iklan native disisipkan setelah kartu ketiga, bukan di
                  // puncak daftar: tiga order teratas adalah yang paling
                  // sering dicari kasir, dan mendorongnya turun akan
                  // memperlambat pekerjaan setiap hari.
                  //
                  // Tidak disisipkan sama sekali bila order sedang dipilih
                  // untuk aksi massal, supaya nomor urut yang dilihat kasir
                  // tidak bergeser di tengah pemilihan.
                  //
                  // Dengan kurang dari tiga order, iklan ditaruh setelah
                  // order terakhir, jadi toko yang masih sepi pun tetap
                  // menayangkan iklan.
                  final groups = groupOrders(list, now);
                  final summary = summarizeOrders(list, now);

                  // Iklan ditaruh setelah kartu ketiga (atau yang terakhir bila
                  // order kurang dari tiga), di dalam kelompok tempat kartu itu
                  // berada, supaya tetap muncul di awal daftar walau satu hari
                  // berisi puluhan order.
                  final adTarget = ads.enabled && _selected.isEmpty
                      ? (list.length >= 3 ? 3 : list.length)
                      : -1;
                  var seen = 0;

                  final sections = <Widget>[];

                  for (final group in groups) {
                    final cards = <Widget>[];
                    var adPlaced = false;

                    for (var i = 0; i < group.orders.length; i++) {
                      final order = group.orders[i];
                      cards.add(_card(order));
                      seen++;

                      if (!adPlaced && adTarget >= 0 && seen == adTarget) {
                        cards.add(const SafeNativeAd(enabled: true));
                        adPlaced = true;
                      }
                    }

                    sections.add(_GroupSection(group: group, cards: cards));
                  }

                  return RefreshIndicator(
                    onRefresh: () async => ref.refreshOrderData(),
                    child: ListView(
                      padding: screenPadding(context, bottom: 96),
                      children: [
                        _SummaryStrip(
                          summary: summary,
                          onTapOutstanding: summary.outstanding > 0
                              ? () => _setFilter(OrderFilter(
                                    unpaidOnly: true,
                                    query: filter.query,
                                  ))
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...sections,
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(int id) {
    if (!_selected.add(id)) _selected.remove(id);
  }

  Widget _card(LaundryOrder order) {
    return _OrderCard(
      order: order,
      selected: _selected.contains(order.id),
      selectionMode: _selected.isNotEmpty,
      onTap: () async {
        if (_selected.isNotEmpty) {
          setState(() => _toggle(order.id!));
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: order.id!),
          ),
        );
        ref.refreshOrderData();
      },
      onLongPress: () => setState(() => _toggle(order.id!)),
    );
  }

  Widget _chip(String label,
      {required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Empat angka ringkas untuk order yang sedang tampil. Mengikuti filter dan
/// pencarian, jadi "Belum lunas" langsung menunjukkan total tagihannya.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, this.onTapOutstanding});

  final OrderListSummary summary;
  final VoidCallback? onTapOutstanding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.status;

    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell(context, 'Order', '${summary.count}'),
            _divider(scheme),
            _cell(context, 'Nilai', formatRupiah(summary.totalValue)),
            _divider(scheme),
            _cell(
              context,
              'Sisa tagihan',
              formatRupiah(summary.outstanding),
              color: summary.outstanding > 0 ? palette.belumLunas : null,
              onTap: onTapOutstanding,
            ),
            _divider(scheme),
            _cell(
              context,
              'Telat',
              '${summary.lateCount}',
              color: summary.lateCount > 0 ? palette.belumLunas : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) =>
      VerticalDivider(width: 1, color: scheme.outlineVariant);

  Widget _cell(BuildContext context, String label, String value,
      {Color? color, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
        ),
      ),
    );
  }
}

/// Satu kelompok order dengan judulnya. Di HP kartu berderet ke bawah, di
/// layar lebar jadi dua atau tiga kolom.
class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.cards});

  final OrderGroup group;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.status;
    final color =
        group.needsAttention ? palette.belumLunas : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, AppSpacing.lg, AppSpacing.xs, AppSpacing.sm),
          child: Row(
            children: [
              if (group.needsAttention) ...[
                Icon(Icons.warning_amber_rounded, size: 18, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                group.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${group.orders.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 320).floor().clamp(1, 3);

            if (columns == 1) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    cards[i],
                  ],
                ],
              );
            }

            final rows = (cards.length / columns).ceil();

            return Column(
              children: [
                for (var r = 0; r < rows; r++) ...[
                  if (r > 0) const SizedBox(height: AppSpacing.md),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0) const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: r * columns + c < cards.length
                                ? cards[r * columns + c]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

IconData _statusIcon(LaundryStatus status) => switch (status.name) {
      'diproses' => Icons.local_laundry_service_outlined,
      'selesai' => Icons.check_circle_outline,
      'diambil' => Icons.shopping_bag_outlined,
      'dibatalkan' => Icons.cancel_outlined,
      _ => Icons.inbox_outlined,
    };

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final LaundryOrder order;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.status;
    final statusColor = palette.forStatus(order.laundryStatus.name);

    // Keterlambatan dihitung dari estimasi selesai. Order yang sudah
    // diambil atau dibatalkan tidak bisa telat lagi.
    final late = order.laundryStatus.isOpen &&
        DateTime.now().isAfter(order.estimatedAt);
    final lateDays = DateTime.now().difference(order.estimatedAt).inDays;
    final unpaid = order.remaining > 0;
    final hasRack = order.rack != null && order.rack!.isNotEmpty;

    final services = order.items.isEmpty
        ? 'Estimasi ${formatDateTime(order.estimatedAt)}'
        : order.items.map((i) => i.serviceName).join(', ');

    return Container(
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: late
              ? palette.belumLunas.withValues(alpha: 0.45)
              : theme.dividerTheme.color ?? Colors.transparent,
        ),
        boxShadow: AppShadow.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Lingkaran berwarna status: bisa disapu mata tanpa
                    // membaca satu kata pun. Saat memilih, berubah jadi
                    // tanda centang.
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : statusColor.withValues(
                                alpha: palette.onStatusTint),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected
                            ? Icons.check
                            : _statusIcon(order.laundryStatus),
                        color: selected ? scheme.onPrimary : statusColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.customerName,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Nomor pendek yang bisa disebut lewat telepon
                          // tanpa tersendat. Nomor panjangnya ada di nota.
                          Text(
                            '${shortOrderNo(order.orderNo)}  ·  '
                            '${formatDateTime(order.createdAt)}',
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRupiah(order.total),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        StatusChip(
                          label: order.laundryStatus.label,
                          color: statusColor,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  services,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusChip(
                      label: unpaid
                          ? 'Sisa ${formatRupiah(order.remaining)}'
                          : 'Lunas',
                      color: unpaid ? palette.belumLunas : palette.lunas,
                      icon: unpaid
                          ? Icons.schedule_outlined
                          : Icons.check_circle_outline,
                      compact: true,
                    ),
                    if (late)
                      StatusChip(
                        label: lateDays < 1
                            ? 'Lewat estimasi hari ini'
                            : 'Telat $lateDays hari',
                        color: palette.belumLunas,
                        icon: Icons.warning_amber_rounded,
                        compact: true,
                      ),
                    // Lokasi rak dibuat menonjol: inilah yang dicari
                    // petugas saat pelanggan berdiri di depan konter.
                    if (hasRack)
                      StatusChip(
                        label: 'Rak ${order.rack}',
                        color: palette.diproses,
                        icon: Icons.inventory_2_outlined,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
