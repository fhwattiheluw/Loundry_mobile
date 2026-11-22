import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
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

                return RefreshIndicator(
                  onRefresh: () async => ref.refreshOrderData(),
                  child: ResponsiveCardGrid(
                    padding: screenPadding(context, bottom: 96),
                    itemCount: list.length,
                    spacing: AppSpacing.md,
                    itemBuilder: (context, i) => _OrderCard(
                      order: list[i],
                      selected: _selected.contains(list[i].id),
                      selectionMode: _selected.isNotEmpty,
                      onTap: () async {
                        if (_selected.isNotEmpty) {
                          setState(() => _toggle(list[i].id!));
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                OrderDetailScreen(orderId: list[i].id!),
                          ),
                        );
                        ref.refreshOrderData();
                      },
                      onLongPress: () => setState(() => _toggle(list[i].id!)),
                    ),
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
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

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
    final statusColor = context.status.forStatus(order.laundryStatus.name);

    // Keterlambatan dihitung dari estimasi selesai. Order yang sudah
    // diambil atau dibatalkan tidak bisa telat lagi.
    final late = order.laundryStatus.isOpen &&
        DateTime.now().isAfter(order.estimatedAt);
    final lateDays = DateTime.now().difference(order.estimatedAt).inDays;

    return Card(
      color: selected ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          // Garis warna di tepi kiri. Inilah yang membuat daftar bisa
          // disapu mata tanpa membaca satu kata pun.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusChip(
                      label: order.laundryStatus.label, color: statusColor),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  // Nomor pendek yang bisa disebut lewat telepon tanpa
                  // tersendat. Nomor panjangnya tetap ada di nota.
                  Text(
                    shortOrderNo(order.orderNo),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '  ·  ${formatDateTime(order.createdAt)}',
                    style:
                        TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (late) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: context.status.belumLunas),
                    const SizedBox(width: 4),
                    Text(
                      lateDays < 1
                          ? 'Lewat estimasi hari ini'
                          : 'Telat $lateDays hari',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.status.belumLunas,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.items.isEmpty
                              ? 'Estimasi ${formatDateTime(order.estimatedAt)}'
                              : order.items.map((i) => i.serviceName).join(', '),
                          style: TextStyle(
                              fontSize: 13.5, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        if (order.remaining > 0)
                          Text(
                            'Sisa ${formatRupiah(order.remaining)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.status.belumLunas,
                            ),
                          )
                        else
                          Text(
                            'Lunas',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.status.lunas,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    formatRupiah(order.total),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
