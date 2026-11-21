import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/stat_tile.dart';
import 'order_detail_screen.dart';

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
            ? null
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const _EmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.refreshOrderData(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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
    final scheme = Theme.of(context).colorScheme;
    final statusColor =
        AppTheme.statusColor(order.laundryStatus.name, scheme);

    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
              Text(
                '${order.orderNo}  ·  ${formatDateTime(order.createdAt)}',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
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
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        if (order.remaining > 0)
                          Text(
                            'Sisa ${formatRupiah(order.remaining)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC62828),
                            ),
                          )
                        else
                          const Text(
                            'Lunas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.inbox_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Center(
            child: Text(
              'Belum ada order di filter ini',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ),
        ],
      );
}
