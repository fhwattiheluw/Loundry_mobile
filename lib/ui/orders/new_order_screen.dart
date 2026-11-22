import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/design_system.dart';
import '../../core/security.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/number_pad.dart';
import 'order_detail_screen.dart';

/// Layar yang paling sering dipakai kasir.
/// Target: satu order kiloan selesai dibuat dan tercetak di bawah 60 detik.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({super.key});

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final _discountController = TextEditingController();
  final _extraFeeController = TextEditingController();
  final _payController = TextEditingController();

  final _items = <OrderItem>[];
  Customer? _customer;
  DateTime? _estimate;
  String? _perfume;
  String _payMethod = 'Tunai';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _discountController.dispose();
    _extraFeeController.dispose();
    _payController.dispose();
    super.dispose();
  }

  int get _subtotal => ref.read(calculatorProvider).subtotalOf(_items);

  int get _discount {
    final raw = parseRupiah(_discountController.text);
    return raw.clamp(0, _subtotal);
  }

  int get _extraFee => parseRupiah(_extraFeeController.text);

  // Diskon hanya memotong nilai layanan. Biaya tambahan seperti antar-jemput
  // adalah ongkos yang sudah terlanjur keluar, jadi tidak ikut didiskon.
  int get _total => _subtotal - _discount + _extraFee;

  int get _payNow => parseRupiah(_payController.text).clamp(0, _total);

  // --------------------------------------------------------------- pelanggan

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerPicker(),
    );

    if (picked == null) return;

    setState(() {
      _customer = picked;
      _nameController.text = picked.name;
      _phoneController.text = prettyPhone(picked.phone);
    });
  }

  // ----------------------------------------------------------------- layanan

  Future<void> _addItem() async {
    final services = await ref.read(servicesProvider.future);

    if (!mounted) return;

    final item = await showModalBottomSheet<OrderItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServicePicker(services: services),
    );

    if (item == null) return;
    setState(() {
      _items.add(item);
      _estimate = null; // dihitung ulang dari layanan terlama
    });
  }

  // ---------------------------------------------------------------- simpan

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);

    if (_items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tambahkan minimal satu layanan.')),
      );
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nama pelanggan belum diisi.')),
      );
      return;
    }

    if (phone.isNotEmpty && !isValidPhone(phone)) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Nomor HP tidak valid. Contoh: 0812-3456-7890')),
      );
      return;
    }

    final settings = ref.read(settingsRepoProvider);
    final user = ref.read(currentUserProvider);
    final maxDiscount =
        settings.getInt(SettingsKeys.maxCashierDiscount, fallback: 0);

    if (!user.isOwner && _discount > maxDiscount) {
      final approved = await _askOwnerPin();
      if (!approved) return;
    }

    setState(() => _saving = true);

    try {
      final customer = await ref.read(customerRepoProvider).saveOrGet(
            _customer ??
                Customer(
                  name: name,
                  phone: phone.isEmpty ? '' : normalizePhone(phone),
                ),
          );

      final services = await ref.read(servicesProvider.future);

      // Pembayaran dikaitkan ke shift yang sedang terbuka, supaya kas laci
      // bisa dicocokkan saat tutup shift. Null bila kasir belum buka shift.
      final shift = await ref.read(currentShiftProvider.future);

      final order = await ref.read(orderRepoProvider).create(
            customer: customer,
            items: _items,
            services: services,
            user: user,
            shiftId: shift?.id,
            discount: _discount,
            extraFee: _extraFee,
            extraFeeNote: _extraFee > 0
                ? ref
                    .read(settingsRepoProvider)
                    .get(SettingsKeys.extraFeeLabel, fallback: 'Biaya lain')
                : null,
            perfume: _perfume,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            estimatedAt: _estimate,
            initialPayment: _payNow,
            paymentMethod: _payMethod,
          );

      if (!mounted) return;
      ref.refreshOrderData();

      // Order sudah tersimpan. Cetak dan notifikasi di bawah ini boleh gagal
      // tanpa membatalkan apa pun (FR-87).
      await _printAndNotify(order);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: order.id!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan order: $e')),
      );
    }
  }

  Future<void> _printAndNotify(LaundryOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);

    final bytes = await ref
        .read(receiptBuilderProvider)
        .buildOrderReceipt(order, cashierName: user.name);

    final result = await ref.read(printerProvider).printBytes(bytes);

    if (!result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Order tersimpan, tapi nota gagal dicetak. '
              '${result.message}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    if (order.customerPhone.isNotEmpty) {
      await ref
          .read(notificationServiceProvider)
          .notify(order, NotificationTrigger.orderDiterima);
    }
  }

  /// Diskon di atas batas butuh persetujuan Owner (FR-44).
  Future<bool> _askOwnerPin() async {
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diskon melebihi batas kasir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan PIN Owner untuk menyetujui diskon ini.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN Owner'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final user =
                  await ref.read(userRepoProvider).authenticate(controller.text);
              if (context.mounted) {
                Navigator.pop(context, user != null && user.isOwner);
              }
            },
            child: const Text('Setujui'),
          ),
        ],
      ),
    );

    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diskon tidak disetujui.')),
      );
    }

    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Order Baru')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Label('Pelanggan'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nama',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Cari pelanggan lama',
                        onPressed: _pickCustomer,
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor WhatsApp',
                      hintText: '0812-3456-7890',
                      prefixIcon: Icon(Icons.chat_outlined),
                      helperText: 'Kosongkan bila pelanggan tidak mau dihubungi',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: _Label('Layanan')),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),

          if (_items.isEmpty)
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _addItem,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Ketuk untuk menambah layanan',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(_items[i].serviceName,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${formatQty(_items[i].qty)} ${_items[i].unit.label}'
                        ' × ${formatRupiah(_items[i].unitPrice)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatRupiah(_items[i].subtotal),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              _items.removeAt(i);
                              _estimate = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 20),
          const _Label('Catatan dan diskon'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan order',
                      hintText: 'Contoh: pisahkan baju putih',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Diskon (Rp)',
                      prefixIcon: Icon(Icons.discount_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _extraFeeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText:
                          '${ref.watch(settingsRepoProvider).get(SettingsKeys.extraFeeLabel, fallback: 'Biaya lain')} (Rp)',
                      helperText: 'Tidak ikut didiskon',
                      prefixIcon: const Icon(Icons.local_shipping_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PerfumePicker(
                    value: _perfume,
                    onChanged: (v) => setState(() => _perfume = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const _Label('Pembayaran'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _payController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Bayar sekarang (Rp)',
                      helperText: 'Kosongkan bila bayar nanti saat diambil',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MethodSelector(
                    value: _payMethod,
                    onChanged: (m) => setState(() => _payMethod = m),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _summaryRow('Subtotal', formatRupiah(_subtotal)),
                  if (_discount > 0)
                    _summaryRow('Diskon', '- ${formatRupiah(_discount)}'),
                  if (_extraFee > 0)
                    _summaryRow(
                      ref.watch(settingsRepoProvider).get(
                          SettingsKeys.extraFeeLabel,
                          fallback: 'Biaya lain'),
                      formatRupiah(_extraFee),
                    ),
                  const Divider(),
                  _summaryRow('Total', formatRupiah(_total), big: true),
                  if (_payNow > 0) ...[
                    _summaryRow('Dibayar', formatRupiah(_payNow)),
                    _summaryRow('Sisa', formatRupiah(_total - _payNow)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan & Cetak Nota'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: big ? 16 : 14,
                    fontWeight: big ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: big ? 20 : 14,
                  fontWeight: big ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );
}

/// Pilihan pewangi (FR-12). Daftarnya diatur pemilik di Pengaturan,
/// karena tiap laundry memakai merek yang berbeda.
class _PerfumePicker extends ConsumerWidget {
  const _PerfumePicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfumes =
        ref.watch(settingsRepoProvider).getList(SettingsKeys.perfumes);

    if (perfumes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parfum', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final perfume in perfumes)
              ChoiceChip(
                label: Text(perfume),
                selected: value == perfume,
                onSelected: (selected) =>
                    onChanged(selected ? perfume : null),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tombol besar yang membuka papan angka, menggantikan kotak isian biasa.
///
/// Berat adalah angka yang paling sering diketik kasir, dan paling sering
/// salah ketik. Papan angka besar mengurangi keduanya.
class _QtyField extends StatelessWidget {
  const _QtyField({
    required this.service,
    required this.value,
    required this.onChanged,
  });

  final LaundryService service;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = value.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () async {
        final result = await showNumberPad(
          context,
          title: 'Jumlah ${service.name}',
          initialValue: value,
          allowDecimal: service.unit.allowsFraction,
          unit: service.unit.label,
          submitLabel: 'Pakai jumlah ini',
          helper: service.minQty > 0
              ? 'Minimal ${formatQty(service.minQty)} ${service.unit.label}'
              : null,
        );

        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Jumlah (${service.unit.label})',
          prefixIcon: const Icon(Icons.scale_outlined),
          suffixIcon: const Icon(Icons.keyboard_arrow_right),
          helperText: service.minQty > 0
              ? 'Minimal ${formatQty(service.minQty)} ${service.unit.label}'
              : 'Ketuk untuk membuka papan angka',
        ),
        child: Text(
          filled ? '$value ${service.unit.label}' : 'Ketuk untuk mengisi',
          style: filled
              ? theme.textTheme.titleMedium
              : theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

class _MethodSelector extends ConsumerWidget {
  const _MethodSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(settingsRepoProvider).getList(
          SettingsKeys.paymentMethods,
        );

    final list = methods.isEmpty ? const ['Tunai'] : methods;

    return Wrap(
      spacing: 8,
      children: [
        for (final method in list)
          ChoiceChip(
            label: Text(method),
            selected: value == method,
            onSelected: (_) => onChanged(method),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- pemilih

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _controller = TextEditingController();
  List<Customer> _results = const [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final found = await ref.read(customerRepoProvider).search(query);
    if (mounted) setState(() => _results = found);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _search,
                decoration: const InputDecoration(
                  hintText: 'Cari nama atau nomor HP',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Pelanggan tidak ditemukan'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.person_outline)),
                        title: Text(_results[i].name),
                        subtitle: Text(prettyPhone(_results[i].phone)),
                        onTap: () => Navigator.pop(context, _results[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicePicker extends ConsumerStatefulWidget {
  const _ServicePicker({required this.services});

  final List<LaundryService> services;

  @override
  ConsumerState<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends ConsumerState<_ServicePicker> {
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  final _detailsController = TextEditingController();

  LaundryService? _service;
  bool _express = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    final service = _service;
    final qty = parseQty(_qtyController.text);

    if (service == null || qty <= 0) return;

    final item = ref.read(calculatorProvider).buildItemWithDetails(
          service,
          qty,
          express: _express,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          itemDetails: _detailsController.text.trim().isEmpty
              ? null
              : _detailsController.text.trim(),
        );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final calc = ref.read(calculatorProvider);
    final qty = parseQty(_qtyController.text);
    final preview = _service == null
        ? 0
        : calc.lineSubtotal(_service!, qty, express: _express);
    final billable =
        _service == null ? 0.0 : calc.billableQty(_service!, qty);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pilih layanan',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final service in widget.services)
                    ChoiceChip(
                      label: Text(
                          '${service.name} · ${formatRupiah(service.price)}/${service.unit.label}'),
                      selected: _service?.id == service.id,
                      onSelected: (_) => setState(() {
                        _service = service;
                        _express = false;
                      }),
                    ),
                ],
              ),
              if (_service != null) ...[
                const SizedBox(height: 16),
                _QtyField(
                  service: _service!,
                  value: _qtyController.text,
                  onChanged: (value) => setState(() {
                    _qtyController.text = value;
                  }),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _express,
                  onChanged: (v) => setState(() => _express = v),
                  title: const Text('Express'),
                  subtitle: Text(
                    'Selesai ${_service!.expressDurationHours} jam, '
                    'harga ×${_service!.expressMultiplier}',
                  ),
                ),
                TextField(
                  controller: _detailsController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Rincian isi (opsional)',
                    hintText: '3 kemeja, 2 celana, 1 jaket',
                    helperText: 'Tercetak di nota, berguna saat ada klaim',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Catatan baris (opsional)',
                  ),
                ),
                const SizedBox(height: 16),
                if (qty > 0 && billable != qty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Ditagih ${formatQty(billable)} ${_service!.unit.label} '
                      'setelah pembulatan dan minimum.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatRupiah(preview),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    FilledButton(
                      onPressed: qty > 0 ? _submit : null,
                      child: const Text('Tambahkan'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
