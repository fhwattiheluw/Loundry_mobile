import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/layout.dart';
import '../widgets/number_pad.dart';

/// Layar pembayaran. Mengembalikan true bila ada pembayaran yang tersimpan.
Future<bool?> showPaymentSheet(
  BuildContext context,
  WidgetRef ref,
  LaundryOrder order,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentSheet(order: order),
  );
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.order});

  final LaundryOrder order;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final _amountController = TextEditingController();
  final _cashController = TextEditingController();

  String _method = 'Tunai';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Bawaan: pelunasan penuh. Kasir tinggal menekan simpan.
    _amountController.text = formatPlain(widget.order.remaining);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  int get _amount =>
      parseRupiah(_amountController.text).clamp(0, widget.order.remaining);

  int get _cash => parseRupiah(_cashController.text);

  int get _change => _cash - _amount;

  Future<void> _save() async {
    if (_amount <= 0 || _saving) return;

    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);

    try {
      final shift = await ref.read(currentShiftProvider.future);

      // Uang tunai tanpa shift terbuka tidak ikut hitungan kas laci saat
      // tutup shift. Kasir perlu tahu SEKARANG, bukan saat selisihnya
      // muncul dan tidak ada yang bisa menjelaskannya.
      if (shift == null && _method == 'Tunai') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Shift belum dibuka, jadi pembayaran tunai ini tidak masuk '
              'hitungan kas shift. Buka shift di menu Pengaturan.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }

      await ref.read(orderRepoProvider).addPayment(
            orderId: widget.order.id!,
            amount: _amount,
            method: _method,
            user: user,
            shiftId: shift?.id,
          );

      final fresh = await ref.read(orderRepoProvider).byId(widget.order.id!);

      if (fresh != null) {
        final payments =
            await ref.read(orderRepoProvider).paymentsOf(widget.order.id!);

        if (payments.isNotEmpty) {
          final bytes = await ref
              .read(receiptBuilderProvider)
              .buildPaymentReceipt(fresh, payments.last,
                  cashierName: user.name);

          final result = await ref.read(printerProvider).printBytes(bytes);

          if (!result.success) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                    'Pembayaran tersimpan, kwitansi gagal dicetak. ${result.message}'),
              ),
            );
          }
        }

        // Pemberitahuan pembayaran diterima (FR-63). Mati secara bawaan,
        // karena pelanggan yang membayar di konter sudah memegang kwitansi.
        await ref.read(notificationServiceProvider).notify(
              fresh,
              NotificationTrigger.pembayaranDiterima,
            );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final methods = ref.watch(settingsRepoProvider).getList(
          SettingsKeys.paymentMethods,
        );
    final methodList = methods.isEmpty ? const ['Tunai'] : methods;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const IconBadge(Icons.payments_outlined, tone: 6),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pembayaran',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          '${order.orderNo}  ·  ${order.customerName}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Tiga angka yang menentukan keputusan kasir, terbaca sekali
              // lihat. Sebelumnya semuanya ditulis sebagai satu baris teks
              // kecil, dan sisa tagihan yang paling penting justru tenggelam.
              _Summary(
                total: order.total,
                paid: order.paid,
                remaining: order.remaining,
              ),
              const SizedBox(height: 18),

              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: rupiahInputFormatters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Jumlah dibayar',
                  prefixText: 'Rp ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.done_all, size: 18),
                    label: const Text('Lunasi'),
                    onPressed: () => setState(() => _amountController.text =
                        formatPlain(order.remaining)),
                  ),
                  ActionChip(
                    label: const Text('Setengah'),
                    onPressed: () => setState(() => _amountController.text =
                        formatPlain(order.remaining ~/ 2)),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final method in methodList)
                    ChoiceChip(
                      label: Text(method),
                      selected: _method == method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),

              if (_method == 'Tunai') ...[
                const SizedBox(height: 18),

                // Pecahan uang yang benar-benar diserahkan pelanggan di
                // konter. Satu ketukan lebih cepat daripada mengetik lima
                // digit, dan tidak bisa salah ketik.
                Text('Uang diterima',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.price_check, size: 18),
                      label: const Text('Uang pas'),
                      onPressed: () => setState(
                          () => _cashController.text = formatPlain(_amount)),
                    ),
                    for (final nominal in const [
                      25000,
                      50000,
                      100000,
                      150000,
                      200000,
                    ])
                      ActionChip(
                        label: Text(formatPlain(nominal)),
                        onPressed: () => setState(() =>
                            _cashController.text = formatPlain(nominal)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () async {
                    final result = await showNumberPad(
                      context,
                      title: 'Uang diterima',
                      initialValue: _cashController.text,
                      isMoney: true,
                      // Tombol papan angka menambah, bukan mengganti, jadi
                      // pecahan kecil berguna di sini.
                      quickValues: const [5000, 10000, 20000, 50000, 100000],
                      submitLabel: 'Hitung kembalian',
                    );
                    if (result != null) {
                      setState(() => _cashController.text = result);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Jumlah lain',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      suffixIcon: Icon(Icons.keyboard_arrow_right),
                      helperText: 'Ketuk untuk membuka papan angka',
                    ),
                    child: Text(
                      _cash > 0 ? formatRupiah(_cash) : 'Ketuk untuk mengisi',
                      style: _cash > 0
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                    ),
                  ),
                ),
                if (_cash > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_change >= 0
                              ? context.status.lunas
                              : context.status.belumLunas)
                          .withValues(alpha: context.status.onStatusTint),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _change >= 0
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _change >= 0 ? 'Kembalian' : 'Uang kurang',
                                style:
                                    Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                formatRupiah(_change.abs()),
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppTouch.primary),
                  ),
                  onPressed: _amount > 0 && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving
                      ? 'Menyimpan...'
                      : 'Simpan & cetak kwitansi'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sisa tagihan sebagai angka terbesar di bidang gradasi, dengan total dan
/// yang sudah dibayar di bawahnya. Sisa adalah angka yang dipakai kasir
/// memutuskan, jadi dialah yang pertama dibaca.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.paid,
    required this.remaining,
  });

  final int total;
  final int paid;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = Colors.white.withValues(alpha: 0.78);

    Widget cell(String label, int value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRupiah(value),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppGradient.brand(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sisa tagihan',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRupiah(remaining),
              style: theme.textTheme.displaySmall
                  ?.copyWith(color: Colors.white, fontSize: 34),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              cell('Total', total),
              cell('Sudah dibayar', paid),
            ],
          ),
        ],
      ),
    );
  }
}
