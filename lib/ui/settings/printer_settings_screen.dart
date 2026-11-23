import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../data/db/settings_keys.dart';
import '../widgets/layout.dart';
import '../../services/printer/receipt_printer.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState
    extends ConsumerState<PrinterSettingsScreen> {
  List<PrinterDevice> _devices = const [];
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    final printer = ref.read(printerProvider);

    if (!await printer.ensurePermissions()) {
      setState(() {
        _loading = false;
        _message =
            'Izin Bluetooth ditolak. Buka pengaturan Android lalu izinkan '
            'aplikasi memakai perangkat di sekitar.';
      });
      return;
    }

    if (!await printer.isBluetoothOn) {
      setState(() {
        _loading = false;
        _message = 'Bluetooth mati. Nyalakan Bluetooth lalu muat ulang.';
      });
      return;
    }

    final devices = await printer.pairedDevices();

    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
      _message = devices.isEmpty
          ? 'Belum ada printer yang dipasangkan. Pasangkan printer lewat '
              'pengaturan Bluetooth Android lebih dulu, baru muat ulang di sini.'
          : null;
    });
  }

  Future<void> _testPrint() async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await ref.read(receiptBuilderProvider).buildTestPage();
    final result = await ref.read(printerProvider).printBytes(bytes, copies: 1);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Uji cetak dikirim. Periksa apakah ada baris yang terpotong.'
            : result.message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsRepoProvider);
    final selected = settings.get(SettingsKeys.printerAddress);
    final paperWidth = settings.get(SettingsKeys.paperWidth, fallback: '58');
    final copies = settings.getInt(SettingsKeys.receiptCopies, fallback: 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Bluetooth'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const Text('Lebar kertas',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '58', label: Text('58 mm')),
                ButtonSegment(value: '80', label: Text('80 mm')),
              ],
              selected: {paperWidth},
              onSelectionChanged: (value) async {
                await settings.set(SettingsKeys.paperWidth, value.first);
                ref.invalidate(settingsLoadedProvider);
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Salah pilih lebar kertas membuat kolom harga terpotong atau '
              'turun baris. Pakai uji cetak untuk memastikan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 20),
            Text('Jumlah salinan nota',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: copies.toDouble().clamp(1, 3),
                    min: 1,
                    max: 3,
                    divisions: 2,
                    label: '$copies',
                    onChanged: (value) async {
                      await settings.set(
                          SettingsKeys.receiptCopies, value.round().toString());
                      ref.invalidate(settingsLoadedProvider);
                      setState(() {});
                    },
                  ),
                ),
                Text('$copies lembar'),
              ],
            ),
            Text(
              'Biasanya 2: satu untuk pelanggan, satu ditempel di cucian.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cetak QR nomor nota'),
              subtitle: const Text(
                'Dipindai saat pengambilan supaya tidak perlu mengetik nomor. '
                'Matikan bila printer Anda tidak mendukung QR.',
              ),
              value: settings.getBool(SettingsKeys.receiptQrEnabled),
              onChanged: (value) async {
                await settings.set(
                    SettingsKeys.receiptQrEnabled, value ? '1' : '0');
                ref.invalidate(settingsLoadedProvider);
                setState(() {});
              },
            ),

            const SizedBox(height: 24),
            Text('Pilih printer',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_message != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const IconBadge(Icons.info_outline, tone: 1),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_message!)),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (address) async {
                    final picked = _devices
                        .where((d) => d.address == address)
                        .firstOrNull;
                    if (picked == null) return;

                    await ref.read(printerProvider).saveDefault(picked);
                    ref.invalidate(settingsLoadedProvider);
                    setState(() {});
                  },
                  child: Column(
                    children: [
                      for (var i = 0; i < _devices.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        RadioListTile<String>(
                          secondary: IconBadge(Icons.print_outlined, tone: i),
                          value: _devices[i].address,
                          title: Text(_devices[i].name),
                          subtitle: Text(_devices[i].address),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppTouch.comfortable),
              ),
              onPressed: selected.isEmpty ? null : _testPrint,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Uji cetak'),
            ),
          ],
        ),
      ),
    );
  }
}
