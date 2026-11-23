import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../services/notification/notification_service.dart';

/// Aksi yang sama dipakai dari baris tombol, menu tiga titik, dan layar
/// sukses. Dikumpulkan di sini supaya perilakunya tidak berbeda-beda
/// tergantung dari mana kasir menekannya.

/// Mencetak ulang nota. Mengembalikan true bila printer berhasil.
Future<bool> reprintOrderReceipt(
  BuildContext context,
  WidgetRef ref,
  LaundryOrder order,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final user = ref.read(currentUserProvider);

  try {
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
    return result.success;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Printer tidak bisa dihubungi.')),
    );
    return false;
  }
}

/// Mengirim pesan ke pelanggan. Pemicunya mengikuti status cucian sekarang,
/// jadi tombol yang sama mengirim "order diterima" di awal dan "cucian
/// selesai" setelah selesai, tanpa kasir perlu memilih.
Future<void> sendOrderWhatsApp(
  BuildContext context,
  WidgetRef ref,
  LaundryOrder order,
) async {
  final trigger = order.laundryStatus == LaundryStatus.selesai
      ? NotificationTrigger.cucianSelesai
      : NotificationTrigger.orderDiterima;

  final messenger = ScaffoldMessenger.of(context);

  final result = await ref
      .read(notificationServiceProvider)
      .notify(order, trigger, force: true);

  ref.invalidate(orderDetailProvider(order.id!));

  if (!result.sent && result.message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }
}
