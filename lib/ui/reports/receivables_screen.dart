import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../orders/order_detail_screen.dart';

/// Daftar piutang, diurutkan dari yang paling lama.
/// Ini layar yang membuat uang tidak hilang diam-diam.
class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(receivablesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Piutang')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 48, color: Color(0xFF2E7D32)),
                    SizedBox(height: 16),
                    Text('Tidak ada piutang. Semua order sudah lunas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            );
          }

          final total = rows.fold(0, (sum, r) => sum + r.remaining);

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total piutang belum tertagih',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      formatRupiah(total),
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                    Text('${rows.length} order',
                        style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final old = row.ageInDays >= 14;

                    return ListTile(
                      title: Text(row.customerName,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${row.orderNo} · ${prettyPhone(row.customerPhone)}\n'
                        'Dibuat ${formatDate(row.createdAt)} · ${row.ageInDays} hari lalu',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatRupiah(row.remaining),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: old ? const Color(0xFFC62828) : null,
                            ),
                          ),
                          if (row.paid > 0)
                            Text('dari ${formatRupiah(row.total)}',
                                style: const TextStyle(
                                    fontSize: 11.5, color: Colors.black54)),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                OrderDetailScreen(orderId: row.orderId),
                          ),
                        );
                        ref.refreshOrderData();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
