import 'package:material_ui/material_ui.dart';

import '../../domain/models/enums.dart';

/// Konfirmasi sebelum status cucian berubah.
///
/// Perubahan status punya akibat yang tidak selalu bisa ditarik kembali:
/// "Selesai" mengirim pesan ke pelanggan, dan "Diambil" menyatakan cucian
/// sudah berpindah tangan. Satu ketukan salah di konter yang ramai cukup
/// untuk mengirim pesan ke orang yang cuciannya belum kering.
///
/// Mengembalikan true hanya bila kasir menyetujui.
Future<bool> confirmStatusChange(
  BuildContext context, {
  required LaundryStatus to,
  required String subject,
  bool willNotifyCustomer = false,
  String? extraWarning,
}) async {
  final consequence = switch (to) {
    LaundryStatus.diproses =>
      'Cucian dinyatakan mulai dikerjakan. Estimasi selesai tidak berubah.',
    LaundryStatus.selesai => willNotifyCustomer
        ? 'Pelanggan akan dikabari bahwa cucian siap diambil.'
        : 'Cucian dinyatakan siap diambil. Pelanggan tidak punya nomor '
            'WhatsApp, jadi tidak ada pesan yang dikirim.',
    LaundryStatus.diambil =>
      'Cucian dinyatakan sudah diserahkan ke pelanggan. Pastikan barangnya '
          'benar-benar sudah dibawa.',
    LaundryStatus.diterima => 'Status dikembalikan ke awal.',
    LaundryStatus.dibatalkan => 'Order dibatalkan.',
  };

  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(_iconFor(to)),
      title: Text('Ubah status ke ${to.label}?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(consequence),
          if (extraWarning != null) ...[
            const SizedBox(height: 10),
            Text(
              extraWarning,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Ya, ${to.label.toLowerCase()}'),
        ),
      ],
    ),
  );

  return approved ?? false;
}

IconData _iconFor(LaundryStatus status) => switch (status) {
      LaundryStatus.diterima => Icons.inbox_outlined,
      LaundryStatus.diproses => Icons.local_laundry_service_outlined,
      LaundryStatus.selesai => Icons.check_circle_outline,
      LaundryStatus.diambil => Icons.handshake_outlined,
      LaundryStatus.dibatalkan => Icons.block,
    };
