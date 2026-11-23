import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../core/design_system.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/payment_banner.dart';
import '../../services/photo/order_photo_service.dart';
import '../widgets/layout.dart';
import '../widgets/actions.dart';
import '../widgets/stat_tile.dart';
import 'order_actions.dart';
import 'payment_sheet.dart';
import 'status_confirm.dart';
import '../../core/friendly_error.dart';
import '../widgets/states.dart';

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
      body: ContentWidth(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            title: 'Order tidak bisa dibuka',
            message: friendlyError(e),
          ),
          data: (order) {
            if (order == null) {
              return const Center(child: Text('Order tidak ditemukan.'));
            }
            return _Body(order: order);
          },
        ),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: AppGradient.brand(context),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadow.soft(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nomor pendek yang bisa disebut lewat telepon.
                        Text(
                          shortOrderNo(order.orderNo),
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.orderNo,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(
                        label: order.laundryStatus.label,
                        color: Colors.white,
                      ),
                      // Lunas dinyatakan di kepala halaman, bukan hanya di
                      // baris angka yang harus digulir untuk ditemukan.
                      if (paymentBannerOf(order) == PaymentBanner.lunas) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const StatusChip(
                          label: 'LUNAS',
                          color: Colors.white,
                          icon: Icons.check_circle,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                order.customerName,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              Text(
                formatDateTime(order.createdAt),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _HeroFigure(
                        label: 'Total',
                        value: formatRupiah(order.total),
                      ),
                    ),
                    Expanded(
                      child: _HeroFigure(
                        label: order.remaining > 0 ? 'Sisa tagihan' : 'Status',
                        value: order.remaining > 0
                            ? formatRupiah(order.remaining)
                            : 'LUNAS',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (order.laundryStatus == LaundryStatus.dibatalkan &&
            order.cancelReason != null) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: IconBadge(Icons.block, color: scheme.error),
              title: const Text('Order dibatalkan'),
              subtitle: Text(order.cancelReason!),
            ),
          ),
        ],

        const SizedBox(height: 16),
        _StatusTimeline(order: order),

        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const IconBadge(Icons.person_outline, tone: 2),
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
                leading: const IconBadge(Icons.schedule_outlined, tone: 3),
                title: const Text('Estimasi selesai'),
                subtitle: Text(formatDateTime(order.estimatedAt)),
              ),
              const Divider(height: 1),
              // Rak bisa diubah kapan saja, bukan hanya saat cucian
              // selesai: kantong sering dipindah saat rak penuh.
              ListTile(
                leading: const IconBadge(Icons.inventory_2_outlined, tone: 4),
                title: const Text('Lokasi rak'),
                subtitle: Text(
                  order.rack == null || order.rack!.isEmpty
                      ? 'Belum ditentukan'
                      : order.rack!,
                  style: order.rack == null || order.rack!.isEmpty
                      ? null
                      : const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => askRack(context, ref, order),
              ),
              if (order.perfume != null && order.perfume!.isNotEmpty) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const IconBadge(Icons.local_florist_outlined, tone: 5),
                  title: const Text('Parfum'),
                  subtitle: Text(order.perfume!),
                ),
              ],
              if (order.note != null && order.note!.isNotEmpty) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const IconBadge(Icons.sticky_note_2_outlined, tone: 6),
                  title: const Text('Catatan'),
                  subtitle: Text(order.note!),
                ),
              ],
              if (order.pickedUpAt != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const IconBadge(Icons.done_all, tone: 7),
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
                            if (item.itemDetails != null &&
                                item.itemDetails!.isNotEmpty)
                              Text(
                                'Isi: ${item.itemDetails}',
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
                if (order.extraFee > 0)
                  _row(
                    context,
                    order.extraFeeNote?.isNotEmpty == true
                        ? order.extraFeeNote!
                        : 'Biaya tambahan',
                    formatRupiah(order.extraFee),
                  ),
                _row(context, 'Total', formatRupiah(order.total), big: true),
                _row(context, 'Sudah dibayar', formatRupiah(order.paid)),
                if (order.remaining > 0)
                  _row(context, 'Sisa tagihan',
                      formatRupiah(order.remaining),
                      big: true, color: context.status.belumLunas)
                else
                  _row(context, 'Status', 'LUNAS',
                      big: true, color: context.status.lunas),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _PhotoCard(orderId: order.id!),

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

/// Menanyakan lokasi rak dan menyimpannya.
///
/// Dipakai dari dua tempat: baris rak di detail order, dan tepat setelah
/// cucian ditandai selesai, karena saat itulah kantongnya benar-benar
/// diletakkan di rak.
Future<void> askRack(
  BuildContext context,
  WidgetRef ref,
  LaundryOrder order,
) async {
  final controller = TextEditingController(text: order.rack ?? '');

  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.inventory_2_outlined),
      title: const Text('Simpan di rak mana?'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 12,
        decoration: const InputDecoration(
          labelText: 'Lokasi rak',
          hintText: 'Contoh: A3',
          helperText: 'Ikut tercetak di nota',
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Lewati'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );

  if (value == null) return;

  await ref.read(orderRepoProvider).setRack(order.id!, value);
  ref.invalidate(orderDetailProvider(order.id!));
  ref.refreshOrderData();
}


/// Foto cucian saat diterima.
///
/// Diletakkan dekat bagian atas, bukan di dasar layar: foto yang harus
/// dicari tidak akan pernah diambil, dan bukti yang tidak diambil tidak
/// menolong siapa pun saat pelanggan datang marah dua hari kemudian.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoCard extends ConsumerWidget {
  const _PhotoCard({required this.orderId});

  final int orderId;

  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final photo = await ref.read(orderPhotoServiceProvider).capture(orderId);
      if (photo != null) ref.invalidate(orderPhotosProvider(orderId));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Foto belum tersimpan. ${friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    OrderPhoto photo,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus foto ini?'),
        content: const Text(
            'Foto tidak bisa dikembalikan setelah dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (yes != true) return;
    await ref.read(orderPhotoServiceProvider).delete(photo);
    ref.invalidate(orderPhotosProvider(orderId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(orderPhotosProvider(orderId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Foto cucian',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                photos.maybeWhen(
                  data: (list) => list.length >= OrderPhotoService.maxPerOrder
                      ? Text('${list.length} foto',
                          style: Theme.of(context).textTheme.bodySmall)
                      : TextButton.icon(
                          onPressed: () => _capture(context, ref),
                          icon: const Icon(Icons.photo_camera_outlined,
                              size: 18),
                          label: Text(list.isEmpty ? 'Ambil foto' : 'Tambah'),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            photos.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Foto belum bisa ditampilkan. ${friendlyError(e)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Belum ada foto. Satu jepretan saat menerima cucian '
                      'menyelesaikan sengketa yang tidak bisa diselesaikan '
                      'catatan angka.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final photo = list[i];
                        return GestureDetector(
                          onTap: () => _openViewer(context, photo),
                          onLongPress: () =>
                              _confirmDelete(context, ref, photo),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              photo.file,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (context, _, __) => Container(
                                width: 92,
                                height: 92,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, OrderPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(child: Image.file(photo.file)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Diambil ${formatDateTime(photo.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
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
                        ? context.status.belumLunas
                        : context.status.lunas,
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
                        ? context.status.lunas
                        : context.status.belumLunas,
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

/// Baris tombol yang menempel di bawah layar.
///
/// Dua aksi pendukung di satu baris, lalu aksi yang mengubah keadaan
/// bertumpuk selebar layar: uang lebih dulu, baru status. Urutan itu
/// mengikuti kebiasaan konter, pelanggan membayar dulu baru cucian
/// diserahkan.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.order});

  final LaundryOrder order;

  Future<void> _advance(BuildContext context, WidgetRef ref) async {
    final next = order.laundryStatus.next;
    if (next == null) return;

    final user = ref.read(currentUserProvider);

    final approved = await confirmStatusChange(
      context,
      to: next,
      subject: '${order.orderNo} · ${order.customerName}',
      willNotifyCustomer: order.customerPhone.isNotEmpty,
      extraWarning: next == LaundryStatus.diambil && order.remaining > 0
          ? 'Sisa tagihan ${formatRupiah(order.remaining)} belum dibayar. '
              'Layar pembayaran akan terbuka dulu.'
          : null,
    );
    if (!approved || !context.mounted) return;

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

    // Saat inilah kantongnya diletakkan di rak, jadi inilah saat yang
    // benar untuk menanyakannya. Ditanyakan belakangan berarti tidak
    // pernah terisi.
    if (next == LaundryStatus.selesai && context.mounted) {
      final fresh = await ref.read(orderRepoProvider).byId(order.id!);
      if (fresh != null && context.mounted) {
        await askRack(context, ref, fresh);
      }
    }

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

    // Cucian diambil: pelanggan sudah pergi dan kasir berhenti sejenak.
    // Ini titik jeda yang wajar. Jeda minimum antar-interstitial ditahan
    // oleh AdService, jadi tidak pernah muncul beruntun.
    if (next == LaundryStatus.diambil) {
      unawaited(
          ref.read(adServiceProvider).showInterstitialAt('cucian diambil'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = order.laundryStatus.next;
    final canAct = order.laundryStatus != LaundryStatus.dibatalkan;
    final hasPhone = order.customerPhone.isNotEmpty;

    // Dua aksi pendukung yang dipakai berkali-kali sehari. Dulu keduanya
    // bersembunyi di menu tiga titik, tempat yang jarang dibuka kasir.
    final secondary = <AppAction>[
      if (hasPhone)
        AppAction(
          label: 'Kirim WA',
          icon: Icons.chat_outlined,
          onPressed: () => sendOrderWhatsApp(context, ref, order),
        ),
      AppAction(
        label: 'Cetak nota',
        icon: Icons.print_outlined,
        onPressed: () => reprintOrderReceipt(context, ref, order),
      ),
    ];

    final primary = <AppAction>[
      if (order.remaining > 0 && canAct)
        AppAction(
          label: 'Terima bayar ${formatRupiah(order.remaining)}',
          icon: Icons.payments_outlined,
          kind: ActionKind.money,
          onPressed: () async {
            final paid = await showPaymentSheet(context, ref, order);
            if (paid == true) {
              ref.invalidate(orderDetailProvider(order.id!));
              ref.refreshOrderData();
            }
          },
        ),
      if (next != null && canAct)
        AppAction(
          label: next.label,
          icon: Icons.arrow_forward,
          kind: ActionKind.primary,
          onPressed: () => _advance(context, ref),
        ),
    ];

    return ActionStack(primary: primary, secondary: secondary);
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.laundryStatus == LaundryStatus.dibatalkan) {
      return const SizedBox.shrink();
    }

    // Cetak ulang dan kirim WhatsApp sudah pindah ke baris tombol di bawah.
    // Yang tersisa di sini hanya aksi merugikan, yang memang sebaiknya
    // butuh dua ketukan.
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'cancel') await _cancel(context, ref);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'cancel',
          child: ListTile(
            leading:
                Icon(Icons.block, color: Theme.of(context).colorScheme.error),
            title: const Text('Batalkan order'),
          ),
        ),
      ],
    );
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

/// Perjalanan satu nota: Diterima, Diproses, Selesai, Diambil.
///
/// Tahap yang sudah dilewati membawa waktu dan nama orang yang mengubahnya,
/// diambil dari tabel status_logs. Tahap yang belum dilewati tetap
/// ditampilkan dalam keadaan pudar, supaya kasir dan pelanggan melihat
/// sisa prosesnya, bukan hanya posisi sekarang.
class _StatusTimeline extends ConsumerStatefulWidget {
  const _StatusTimeline({required this.order});

  final LaundryOrder order;

  static const flow = [
    LaundryStatus.diterima,
    LaundryStatus.diproses,
    LaundryStatus.selesai,
    LaundryStatus.diambil,
  ];

  @override
  ConsumerState<_StatusTimeline> createState() => _StatusTimelineState();
}

class _StatusTimelineState extends ConsumerState<_StatusTimeline> {
  /// Tertutup secara bawaan.
  ///
  /// Dalam bentuk memanjang, tiga baris "Belum" memakan hampir separuh
  /// layar pertama untuk mengabarkan hal yang belum terjadi, dan mendorong
  /// total serta tombol aksi ke bawah lipatan. Riwayat lengkapnya tetap
  /// ada, satu ketukan jauhnya.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.watch(orderRepoProvider).statusHistory(order.id!),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const <Map<String, Object?>>[];

        // Satu status bisa tercatat lebih dari sekali bila kasir
        // memundurkannya. Yang ditampilkan adalah catatan terakhir.
        final lastOf = <String, Map<String, Object?>>{};
        for (final log in logs) {
          lastOf[log['status'] as String] = log;
        }

        final cancelled = order.laundryStatus == LaundryStatus.dibatalkan;
        const flow = _StatusTimeline.flow;
        final currentIndex = flow.indexOf(order.laundryStatus);

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, _expanded ? 6 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Perjalanan order',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_expanded)
                    for (var i = 0; i < flow.length; i++)
                      _Step(
                        status: flow[i],
                        log: lastOf[flow[i].name],
                        done: !cancelled && currentIndex >= i,
                        current: !cancelled && currentIndex == i,
                        isLast: i == flow.length - 1 && !cancelled,
                      )
                  else
                    _CompactFlow(
                      flow: flow,
                      currentIndex: cancelled ? -1 : currentIndex,
                      cancelled: cancelled,
                    ),

                  if (_expanded && cancelled)
                    _Step(
                      status: LaundryStatus.dibatalkan,
                      log: lastOf[LaundryStatus.dibatalkan.name],
                      done: true,
                      current: true,
                      isLast: true,
                    ),

                  if (!_expanded) ...[
                    const SizedBox(height: 10),
                    Text(
                      _summaryLine(order, lastOf, cancelled),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _summaryLine(
    LaundryOrder order,
    Map<String, Map<String, Object?>> lastOf,
    bool cancelled,
  ) {
    final log = lastOf[order.laundryStatus.name];
    final changedAt = log?['changed_at'] as String?;
    final userName = log?['user_name'] as String?;

    final label = cancelled ? 'Dibatalkan' : order.laundryStatus.label;
    if (changedAt == null) return label;

    final when = formatDateTime(DateTime.parse(changedAt));
    return '$label \u00b7 $when${userName == null ? '' : ' \u00b7 $userName'}';
  }
}

/// Empat titik dalam satu baris. Terbaca sekali lihat, dan tidak memakan
/// tempat yang dibutuhkan angka dan tombol di bawahnya.
class _CompactFlow extends StatelessWidget {
  const _CompactFlow({
    required this.flow,
    required this.currentIndex,
    required this.cancelled,
  });

  final List<LaundryStatus> flow;
  final int currentIndex;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (cancelled) {
      return Row(
        children: [
          Icon(Icons.block, size: 18, color: context.status.dibatalkan),
          const SizedBox(width: 8),
          Text(
            'Order dibatalkan',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.status.dibatalkan,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < flow.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 18),
                color: currentIndex >= i
                    ? context.status.forStatus(flow[i].name)
                    : scheme.outlineVariant,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(
                color: context.status.forStatus(flow[i].name),
                done: currentIndex >= i,
                current: currentIndex == i,
                muted: scheme.outlineVariant,
                surface: scheme.surface,
              ),
              const SizedBox(height: 4),
              Text(
                flow[i].label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      currentIndex == i ? FontWeight.w700 : FontWeight.w400,
                  color: currentIndex >= i ? null : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.done,
    required this.current,
    required this.muted,
    required this.surface,
  });

  final Color color;
  final bool done;
  final bool current;
  final Color muted;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: current ? 24 : 20,
      height: current ? 24 : 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: Border.all(color: done ? color : muted, width: 2),
      ),
      child: done
          ? Icon(current ? Icons.circle : Icons.check,
              size: current ? 10 : 12, color: surface)
          : null,
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.status,
    required this.log,
    required this.done,
    required this.current,
    required this.isLast,
  });

  final LaundryStatus status;
  final Map<String, Object?>? log;
  final bool done;
  final bool current;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done
        ? context.status.forStatus(status.name)
        : scheme.onSurfaceVariant.withValues(alpha: 0.4);

    final changedAt = log?['changed_at'] as String?;
    final userName = log?['user_name'] as String?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bulatan tahap dan garis penghubung ke tahap berikutnya.
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? color : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? Icon(
                      current ? Icons.circle : Icons.check,
                      size: 12,
                      color: scheme.surface,
                    )
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30,
                color: color.withValues(alpha: done ? 0.5 : 0.25),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                    color: done ? null : scheme.onSurfaceVariant,
                  ),
                ),
                if (changedAt != null)
                  Text(
                    '${formatDateTime(DateTime.parse(changedAt))}'
                    '${userName == null ? '' : ' \u00b7 $userName'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  Text(
                    'Belum',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
