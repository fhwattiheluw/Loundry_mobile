import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/layout.dart';
import '../widgets/stat_tile.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';

/// Layar penutup setelah order tersimpan.
///
/// Dulu kasir langsung dilempar ke detail order. Layar ini memberi
/// kepastian ("order sudah masuk, nomornya ini, nota begini") dan satu
/// langkah berikutnya yang jelas, terutama "Order baru" untuk antrean
/// pelanggan di depan konter.
class OrderSuccessScreen extends ConsumerStatefulWidget {
  const OrderSuccessScreen({
    super.key,
    required this.order,
    this.printError,
    this.whatsappNote,
  });

  final LaundryOrder order;

  /// Pesan bila nota gagal tercetak. Null berarti tercetak.
  final String? printError;

  /// Keterangan hasil WhatsApp otomatis bila ada yang perlu diketahui kasir.
  final String? whatsappNote;

  @override
  ConsumerState<OrderSuccessScreen> createState() =>
      _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends ConsumerState<OrderSuccessScreen> {
  late String? _printError = widget.printError;
  bool _printing = false;
  bool _sending = false;

  LaundryOrder get _order => widget.order;

  Future<void> _print() async {
    setState(() => _printing = true);

    try {
      final user = ref.read(currentUserProvider);
      final bytes = await ref.read(receiptBuilderProvider).buildOrderReceipt(
            _order,
            cashierName: user.name,
            isReprint: _printError == null,
          );
      final result = await ref.read(printerProvider).printBytes(bytes);

      if (!mounted) return;
      setState(() => _printError = result.success ? null : result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _printError = 'Printer tidak bisa dihubungi.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);

    try {
      final result = await ref
          .read(notificationServiceProvider)
          .notify(_order, NotificationTrigger.orderDiterima, force: true);

      if (!result.sent && result.message.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openDetail() {
    Navigator.of(context).pushReplacement<bool, bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OrderDetailScreen(orderId: _order.id!),
      ),
      result: true,
    );
  }

  void _newOrder() {
    Navigator.of(context).pushReplacement<bool, bool>(
      MaterialPageRoute<bool>(builder: (_) => const NewOrderScreen()),
      result: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.status;
    final hasPhone = _order.customerPhone.isNotEmpty;

    final paid = _order.paymentStatus;
    final payColor = paid == PaymentStatus.lunas
        ? palette.lunas
        : palette.belumLunas;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Order Tersimpan'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Selesai'),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: ContentWidth(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, AppTouch.primary),
                ),
                onPressed: _newOrder,
                icon: const Icon(Icons.add),
                label: const Text('Order Baru'),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(context.screenPadding),
          child: ContentWidth(
            maxWidth: 560,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.lg),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: AppDuration.slow,
                  curve: Curves.easeOutBack,
                  builder: (_, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: palette.lunas.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded,
                        size: 52, color: palette.lunas),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Order berhasil dibuat',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  shortOrderNo(_order.orderNo),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  _order.orderNo,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        _row(
                          'Pelanggan',
                          _order.customerName,
                          sub: hasPhone ? _order.customerPhone : null,
                        ),
                        _row(
                          'Layanan',
                          '${_order.items.length} jenis',
                        ),
                        _row(
                          'Perkiraan selesai',
                          formatDateTime(_order.estimatedAt),
                        ),
                        const Divider(height: AppSpacing.xxl),
                        _row('Total', formatRupiah(_order.total),
                            bold: true),
                        if (_order.paid > 0)
                          _row('Dibayar', formatRupiah(_order.paid)),
                        if (_order.remaining > 0)
                          _row('Sisa tagihan',
                              formatRupiah(_order.remaining)),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: StatusChip(
                            label: paid == PaymentStatus.belumBayar
                                ? 'Bayar nanti · masuk Piutang'
                                : paid.label,
                            color: payColor,
                            icon: paid == PaymentStatus.lunas
                                ? Icons.check_circle_outline
                                : Icons.schedule_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _printCard(scheme, palette),
                if (widget.whatsappNote != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.whatsappNote!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (hasPhone) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize:
                                const Size(0, AppTouch.comfortable),
                          ),
                          onPressed: _sending ? null : _sendWhatsApp,
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Kirim WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppTouch.comfortable),
                        ),
                        onPressed: _openDetail,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Lihat Detail'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _printCard(ColorScheme scheme, StatusPalette palette) {
    final failed = _printError != null;
    final color = failed ? palette.belumLunas : palette.lunas;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.print_disabled_outlined : Icons.print_outlined,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              failed
                  ? 'Nota belum tercetak. $_printError'
                  : 'Nota sudah dicetak.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _printing ? null : _print,
            child: Text(_printing
                ? 'Mencetak...'
                : failed
                    ? 'Coba lagi'
                    : 'Cetak ulang'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {String? sub, bool bold = false}) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: bold ? 20 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (sub != null)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
