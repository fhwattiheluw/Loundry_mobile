import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../services/ads/ad_service.dart';
import '../widgets/layout.dart';
import '../widgets/states.dart';
import '../widgets/stat_tile.dart';
import 'order_detail_screen.dart';
import 'scan_order_screen.dart';
import 'status_confirm.dart';

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
      body: Column(
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
                message: '$e',
                onRetry: () => ref.refreshOrderData(),
              ),
              data: (raw) {
                // Yang telat naik ke atas, yang paling lama telat paling
                // dulu. Di konter, tumpukan yang terlupakan itulah yang
                // harus terlihat pertama, bukan order yang baru saja masuk.
                final list = [...raw]..sort((a, b) {
                    final now = DateTime.now();
                    final aLate =
                        a.laundryStatus.isOpen && now.isAfter(a.estimatedAt);
                    final bLate =
                        b.laundryStatus.isOpen && now.isAfter(b.estimatedAt);
                    if (aLate != bLate) return aLate ? -1 : 1;
                    if (aLate && bLate) {
                      return a.estimatedAt.compareTo(b.estimatedAt);
                    }
                    return 0;
                  });

                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Belum ada order di filter ini',
                    message: filter.statuses.isEmpty && !filter.unpaidOnly
                        ? 'Order baru akan muncul di sini.'
                        : 'Coba pilih filter lain di atas.',
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
                final adAt = ads.enabled && _selected.isEmpty
                    ? (list.length >= 3 ? 3 : list.length)
                    : -1;

                return RefreshIndicator(
                  onRefresh: () async => ref.refreshOrderData(),
                  child: ResponsiveCardGrid(
                    padding: screenPadding(context, bottom: 96),
                    itemCount: list.length + (adAt >= 0 ? 1 : 0),
                    spacing: AppSpacing.md,
                    itemBuilder: (context, i) {
                      if (adAt >= 0 && i == adAt) {
                        return const SafeNativeAd(enabled: true);
                      }

                      final order = list[adAt >= 0 && i > adAt ? i - 1 : i];

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
                              builder: (_) =>
                                  OrderDetailScreen(orderId: order.id!),
                            ),
                          );
                          ref.refreshOrderData();
                        },
                        onLongPress: () => setState(() => _toggle(order.id!)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(int id) {
    if (!_selected.add(id)) _selected.remove(id);
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
