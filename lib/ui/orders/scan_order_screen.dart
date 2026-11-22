import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../application/providers.dart';
import 'order_detail_screen.dart';

/// Memindai QR nomor nota saat pelanggan datang mengambil cucian (FR-33).
///
/// Jauh lebih cepat daripada mengetik nomor nota, dan tidak mungkin salah
/// ketik. Kalau QR tidak terbaca, kasir tetap bisa mengetik nomornya.
class ScanOrderScreen extends ConsumerStatefulWidget {
  const ScanOrderScreen({super.key});

  @override
  ConsumerState<ScanOrderScreen> createState() => _ScanOrderScreenState();
}

class _ScanOrderScreenState extends ConsumerState<ScanOrderScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(String code) async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _error = null;
    });

    final order = await ref.read(orderRepoProvider).byOrderNo(code);

    if (!mounted) return;

    if (order == null) {
      setState(() {
        _handling = false;
        _error = 'Nota $code tidak ditemukan.';
      });
      return;
    }

    await _controller.stop();

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(orderId: order.id!),
      ),
    );
  }

  Future<void> _typeManually() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ketik nomor nota'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '20261122-007'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Cari'),
          ),
        ],
      ),
    );

    if (code != null && code.isNotEmpty) await _open(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pindai Nota'),
        actions: [
          IconButton(
            tooltip: 'Nyalakan senter',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Ketik nomor',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: _typeManually,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code.isNotEmpty) _open(code);
            },
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Kamera tidak bisa dipakai.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text('${error.errorCode}', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _typeManually,
                      icon: const Icon(Icons.keyboard_outlined),
                      label: const Text('Ketik nomor nota'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFCDD2),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const Text(
                    'Arahkan kamera ke QR pada nota pelanggan',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
