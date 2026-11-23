import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/security.dart';
import '../../domain/models/models.dart';
import '../widgets/layout.dart';
import '../widgets/states.dart';
import 'broadcast_screen.dart';
import 'customer_sheet.dart';
import '../../core/friendly_error.dart';

class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key});

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  final _searchController = TextEditingController();

  List<Customer> _customers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final rows =
        await ref.read(customerRepoProvider).search(query, limit: 200);
    if (mounted) {
      setState(() {
        _customers = rows;
        _loading = false;
      });
    }
  }

  /// Impor CSV (FR-13).
  ///
  /// Format yang diterima sengaja longgar: kolom pertama nama, kolom kedua
  /// nomor HP. Baris judul dilewati otomatis. Pemisah koma maupun titik koma
  /// sama-sama dikenali, karena Excel Indonesia memakai titik koma.
  Future<void> _import() async {
    // Messenger diambil SEBELUM await, karena setelah pemilih berkas
    // ditutup widget ini bisa saja sudah dilepas dari pohon.
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;

    try {
      var text = await File(path).readAsString();
      if (text.startsWith('﻿')) text = text.substring(1);

      final delimiter = text.contains(';') ? ';' : ',';
      final rows = CsvToListConverter(
        fieldDelimiter: delimiter,
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(text.replaceAll('\r\n', '\n'));

      final parsed = <Customer>[];

      for (final row in rows) {
        if (row.length < 2) continue;

        final name = '${row[0]}'.trim();
        final phone = '${row[1]}'.trim();

        // Baris judul: kolom kedua jelas bukan nomor.
        if (parsed.isEmpty && !RegExp(r'[0-9]').hasMatch(phone)) continue;

        parsed.add(Customer(
          name: name,
          phone: phone,
          address: row.length > 2 ? '${row[2]}'.trim() : null,
        ));
      }

      if (parsed.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak ada baris yang bisa dibaca. Pastikan kolom pertama nama '
              'dan kolom kedua nomor HP.',
            ),
          ),
        );
        return;
      }

      final report = await ref.read(customerRepoProvider).importMany(parsed);
      await _load(_searchController.text);

      messenger.showSnackBar(
        SnackBar(
          content: Text(report.summary),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Berkas tidak bisa diimpor. ${friendlyError(e)} '
            'Pastikan berkasnya berformat CSV.',
          ),
        ),
      );
    }
  }

  Future<void> _edit(Customer customer) async {
    final nameController = TextEditingController(text: customer.name);
    final phoneController =
        TextEditingController(text: prettyPhone(customer.phone));
    final addressController = TextEditingController(text: customer.address);
    var notify = customer.notifyEnabled;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ubah pelanggan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Nomor WhatsApp'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: notify,
                  onChanged: (v) => setDialogState(() => notify = v),
                  title: const Text('Boleh dikirimi notifikasi'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final phone = phoneController.text.trim();
    if (phone.isNotEmpty && !isValidPhone(phone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nomor HP tidak valid.')),
        );
      }
      return;
    }

    await ref.read(customerRepoProvider).update(
          Customer(
            id: customer.id,
            name: nameController.text.trim(),
            phone: phone,
            address: addressController.text.trim().isEmpty
                ? null
                : addressController.text.trim(),
            note: customer.note,
            notifyEnabled: notify,
          ),
        );

    await _load(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(sessionProvider)?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          if (isOwner)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'import') {
                  _import();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const BroadcastScreen()),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.upload_file_outlined),
                    title: Text('Impor dari CSV'),
                  ),
                ),
                PopupMenuItem(
                  value: 'broadcast',
                  child: ListTile(
                    leading: Icon(Icons.campaign_outlined),
                    title: Text('Kirim promo'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ContentWidth(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _load,
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor HP',
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
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? EmptyState(
                        icon: _searchController.text.trim().isEmpty
                            ? Icons.people_outline
                            : Icons.search_off,
                        title: _searchController.text.trim().isEmpty
                            ? 'Belum ada pelanggan'
                            : 'Pelanggan tidak ditemukan',
                        message: _searchController.text.trim().isEmpty
                            ? 'Pelanggan tersimpan otomatis saat Anda '
                                'membuat order. Anda juga bisa mengimpor '
                                'daftar dari berkas CSV.'
                            : 'Coba nama atau nomor HP yang lain. '
                                'Pelanggan baru tersimpan otomatis saat '
                                'Anda membuat order.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final customer = _customers[i];
                          return Card(
                              child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: IconBadge.tones[
                                      customer.name.length %
                                          IconBadge.tones.length]
                                  .withValues(alpha: 0.15),
                              foregroundColor: IconBadge.tones[
                                  customer.name.length %
                                      IconBadge.tones.length],
                              child: Text(
                                customer.name.isEmpty
                                    ? '?'
                                    : customer.name
                                        .substring(0, 1)
                                        .toUpperCase(),
                              ),
                            ),
                            title: Text(customer.name),
                            subtitle: Text(
                              customer.phone.isEmpty
                                  ? 'Tanpa nomor'
                                  : prettyPhone(customer.phone),
                            ),
                            trailing: customer.notifyEnabled
                                ? null
                                : const Icon(Icons.notifications_off_outlined,
                                    size: 18),
                            onTap: () => showCustomerSheet(
                              context,
                              customer,
                              onEdit: () => _edit(customer),
                            ),
                          ));
                        },
                      ),
          ),
        ],
      )),
    );
  }
}
