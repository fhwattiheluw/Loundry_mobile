import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/stat_tile.dart';
import 'payment_sheet.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Order'),
        actions: [
          async.maybeWhen(
            data: (order) => order == null
                ? const SizedBox.shrink()
                : _OverflowMenu(order: order),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Order tidak ditemukan.'));
          }
          return _Body(order: order);
        },
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (order) =>
            order == null ? null : _ActionBar(order: order),
        orElse: () => null,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = AppTheme.statusColor(order.laundryStatus.name, scheme);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.orderNo,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(formatDateTime(order.createdAt),
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            StatusChip(label: order.laundryStatus.label, color: statusColor),
          ],
        ),

        if (order.laundryStatus == LaundryStatus.dibatalkan &&
            order.cancelReason != null) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Order dibatalkan'),
              subtitle: Text(order.cancelReason!),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(order.customerName),
                subtitle: Text(order.customerPhone.isEmpty
                    ? 'Tanpa nomor WhatsApp'
                    : prettyPhone(order.customerPhone)),
                trailing: order.customerPhone.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Salin nomor',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: order.customerPhone));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nomor disalin.')),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Estimasi selesai'),
                subtitle: Text(formatDateTime(order.estimatedAt)),
              ),
              if (order.note != null && order.note!.isNotEmpty) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: const Text('Catatan'),
                  subtitle: Text(order.note!),
                ),
              ],
              if (order.pickedUpAt != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.done_all),
                  title: const Text('Diambil'),
                  subtitle: Text(
                    '${formatDateTime(order.pickedUpAt!)}'
                    '${order.pickedUpBy != null ? ' oleh ${order.pickedUpBy}' : ''}',
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final item in order.items) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.serviceName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${formatQty(item.qty)} ${item.unit.label} × ${formatRupiah(item.unitPrice)}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                            if (item.note != null && item.note!.isNotEmpty)
                              Text(item.note!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Text(formatRupiah(item.subtotal),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(),
                _row(context, 'Subtotal', formatRupiah(order.subtotal)),
                if (order.discount > 0)
                  _row(context, 'Diskon', '- ${formatRupiah(order.discount)}'),
                _row(context, 'Total', formatRupiah(order.total), big: true),
                _row(context, 'Sudah dibayar', formatRupiah(order.paid)),
                if (order.remaining > 0)
                  _row(context, 'Sisa tagihan',
                      formatRupiah(order.remaining),
                      big: true, color: const Color(0xFFC62828))
                else
                  _row(context, 'Status', 'LUNAS',
                      big: true, color: const Color(0xFF2E7D32)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _PaymentHistory(orderId: order.id!),
        const SizedBox(height: 16),
        _NotificationHistory(orderId: order.id!),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool big = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: big ? 15 : 13.5,
                    fontWeight: big ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: big ? 18 : 13.5,
                  fontWeight: big ? FontWeight.w700 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _PaymentHistory extends ConsumerWidget {
  const _PaymentHistory({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Payment>>(
      future: ref.watch(orderRepoProvider).paymentsOf(orderId),
      builder: (context, snapshot) {
        final payments = snapshot.data ?? const <Payment>[];
        if (payments.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('Riwayat pembayaran',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final payment in payments)
                ListTile(
                  dense: true,
                  leading: Icon(
                    payment.isRefund
                        ? Icons.undo
                        : Icons.check_circle_outline,
                    color: payment.isRefund
                        ? const Color(0xFFC62828)
                        : const Color(0xFF2E7D32),
                  ),
                  title: Text(formatRupiah(payment.amount)),
                  subtitle: Text(
                      '${payment.method} · ${formatDateTime(payment.paidAt)}'
                      '${payment.note != null ? '\n${payment.note}' : ''}'),
                  isThreeLine: payment.note != null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationHistory extends ConsumerWidget {
  const _NotificationHistory({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.watch(notificationServiceProvider).historyOf(orderId),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const [];
        if (logs.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('Riwayat notifikasi',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final log in logs)
                ListTile(
                  dense: true,
                  leading: Icon(
                    log['status'] == 'terkirim'
                        ? Icons.mark_chat_read_outlined
                        : Icons.error_outline,
                    color: log['status'] == 'terkirim'
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                  title: Text(
                    NotificationTrigger.fromDb(log['trigger_name'] as String).label,
                  ),
                  subtitle: Text(
                    '${formatDateTime(DateTime.parse(log['sent_at'] as String))}'
                    '${log['error'] != null ? '\n${log['error']}' : ''}',
                  ),
                  isThreeLine: log['error'] != null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tombol aksi utama. Yang paling sering dipakai diletakkan paling kanan,
/// di jangkauan ibu jari.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.order});

  final LaundryOrder order;

  Future<void> _advance(BuildContext context, WidgetRef ref) async {
    final next = order.laundryStatus.next;
    if (next == null) return;

    final user = ref.read(currentUserProvider);

    // Cucian yang diambil tapi belum lunas harus lewat layar pembayaran dulu.
    if (next == LaundryStatus.diambil && order.remaining > 0) {
      final paid = await showPaymentSheet(context, ref, order);
      if (paid != true) return;
    }

    await ref
        .read(orderRepoProvider)
        .changeStatus(order.id!, next, user: user);

    ref.invalidate(orderDetailProvider(order.id!));
    ref.refreshOrderData();

    if (!context.mounted) return;

    if (next == LaundryStatus.selesai && order.customerPhone.isNotEmpty) {
      final fresh = await ref.read(orderRepoProvider).byId(order.id!);
      if (fresh != null) {
        await ref
            .read(notificationServiceProvider)
            .notify(fresh, NotificationTrigger.cucianSelesai);
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status diubah ke ${next.label}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = order.laundryStatus.next;
    final canAct = order.laundryStatus != LaundryStatus.dibatalkan;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (order.remaining > 0 && canAct) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final paid = await showPaymentSheet(context, ref, order);
                    if (paid == true) {
                      ref.invalidate(orderDetailProvider(order.id!));
                      ref.refreshOrderData();
                    }
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Bayar'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (next != null && canAct)
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _advance(context, ref),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(next.label),
                ),
              )
            else
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _reprint(context, ref),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Cetak ulang nota'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);

    final bytes = await ref.read(receiptBuilderProvider).buildOrderReceipt(
          order,
          cashierName: user.name,
          isReprint: true,
        );

    final result = await ref.read(printerProvider).printBytes(bytes);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Nota dicetak ulang.'
            : 'Gagal mencetak. ${result.message}'),
      ),
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'reprint':
            await _reprint(context, ref);
          case 'wa':
            await _sendWhatsApp(context, ref);
          case 'cancel':
            await _cancel(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'reprint',
          child: ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Cetak ulang nota'),
          ),
        ),
        if (order.customerPhone.isNotEmpty)
          const PopupMenuItem(
            value: 'wa',
            child: ListTile(
              leading: Icon(Icons.chat_outlined),
              title: Text('Kirim WhatsApp'),
            ),
          ),
        if (order.laundryStatus != LaundryStatus.dibatalkan)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(Icons.block, color: Color(0xFFC62828)),
              title: Text('Batalkan order'),
            ),
          ),
      ],
    );
  }

  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);

    final bytes = await ref.read(receiptBuilderProvider).buildOrderReceipt(
          order,
          cashierName: user.name,
          isReprint: true,
        );

    final result = await ref.read(printerProvider).printBytes(bytes);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Nota dicetak ulang.'
            : 'Gagal mencetak. ${result.message}'),
      ),
    );
  }

  Future<void> _sendWhatsApp(BuildContext context, WidgetRef ref) async {
    final trigger = order.laundryStatus == LaundryStatus.selesai
        ? NotificationTrigger.cucianSelesai
        : NotificationTrigger.orderDiterima;

    final messenger = ScaffoldMessenger.of(context);

    final result = await ref
        .read(notificationServiceProvider)
        .notify(order, trigger, force: true);

    ref.invalidate(orderDetailProvider(order.id!));

    if (!result.sent) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final user = ref.read(currentUserProvider);

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Order tidak dihapus, hanya ditandai batal. Alasan wajib diisi.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Alasan'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Batalkan order'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(orderRepoProvider)
          .cancel(order.id!, user: user, reason: reason);

      ref.invalidate(orderDetailProvider(order.id!));
      ref.refreshOrderData();

      messenger.showSnackBar(
        const SnackBar(content: Text('Order dibatalkan.')),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
