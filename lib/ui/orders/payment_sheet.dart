import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/models.dart';

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
    _amountController.text = widget.order.remaining.toString();
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
      await ref.read(orderRepoProvider).addPayment(
            orderId: widget.order.id!,
            amount: _amount,
            method: _method,
            user: user,
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
              Text('Pembayaran ${order.orderNo}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Total ${formatRupiah(order.total)} · sudah dibayar ${formatRupiah(order.paid)}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Jumlah dibayar (Rp)',
                  helperText: 'Sisa tagihan ${formatRupiah(order.remaining)}',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Lunasi'),
                    onPressed: () => setState(() =>
                        _amountController.text = order.remaining.toString()),
                  ),
                  ActionChip(
                    label: const Text('Setengah'),
                    onPressed: () => setState(() => _amountController.text =
                        (order.remaining ~/ 2).toString()),
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
                const SizedBox(height: 16),
                TextField(
                  controller: _cashController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Uang diterima (Rp)',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
                if (_cash > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _change >= 0
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _change >= 0
                          ? 'Kembalian ${formatRupiah(_change)}'
                          : 'Uang kurang ${formatRupiah(-_change)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
