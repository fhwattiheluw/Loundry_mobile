import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

class ServiceSettingsScreen extends ConsumerWidget {
  const ServiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Layanan dan harga')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Layanan baru'),
      ),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final service = list[i];
            return ListTile(
              title: Text(service.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${formatRupiah(service.price)} / ${service.unit.label}'
                ' · selesai ${service.durationHours} jam'
                '${service.minQty > 0 ? ' · min ${formatQty(service.minQty)}' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    _edit(context, ref, service);
                  } else {
                    await ref
                        .read(serviceRepoProvider)
                        .deactivate(service.id!);
                    ref.invalidate(servicesProvider);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Ubah')),
                  PopupMenuItem(
                      value: 'off', child: Text('Nonaktifkan')),
                ],
              ),
              onTap: () => _edit(context, ref, service),
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LaundryService? service,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceForm(service: service),
    );

    if (saved == true) ref.invalidate(servicesProvider);
  }
}

class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({this.service});

  final LaundryService? service;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _minQty;
  late final TextEditingController _rounding;
  late final TextEditingController _expressMultiplier;
  late final TextEditingController _expressDuration;

  late ServiceUnit _unit;

  @override
  void initState() {
    super.initState();
    final s = widget.service;

    _name = TextEditingController(text: s?.name ?? '');
    _price = TextEditingController(
        text: s == null ? '' : formatPlain(s.price));
    _duration = TextEditingController(text: s?.durationHours.toString() ?? '48');
    _minQty = TextEditingController(text: formatQty(s?.minQty ?? 0));
    _rounding = TextEditingController(text: formatQty(s?.roundingStep ?? 0));
    _expressMultiplier =
        TextEditingController(text: (s?.expressMultiplier ?? 2.0).toString());
    _expressDuration =
        TextEditingController(text: (s?.expressDurationHours ?? 6).toString());
    _unit = s?.unit ?? ServiceUnit.kg;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _minQty.dispose();
    _rounding.dispose();
    _expressMultiplier.dispose();
    _expressDuration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final service = LaundryService(
      id: widget.service?.id,
      name: name,
      unit: _unit,
      price: parseRupiah(_price.text),
      durationHours: int.tryParse(_duration.text) ?? 48,
      minQty: parseQty(_minQty.text),
      roundingStep: parseQty(_rounding.text),
      expressMultiplier: double.tryParse(
              _expressMultiplier.text.replaceAll(',', '.')) ??
          2.0,
      expressDurationHours: int.tryParse(_expressDuration.text) ?? 6,
    );

    final repo = ref.read(serviceRepoProvider);
    if (widget.service == null) {
      await repo.insert(service);
    } else {
      await repo.update(service);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
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
              Text(
                widget.service == null ? 'Layanan baru' : 'Ubah layanan',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama layanan'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final unit in ServiceUnit.values)
                    ChoiceChip(
                      label: Text(unit.label),
                      selected: _unit == unit,
                      onSelected: (_) => setState(() => _unit = unit),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: rupiahInputFormatters,
                decoration: InputDecoration(
                  labelText: 'Harga per ${_unit.label}',
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durasi pengerjaan (jam)',
                  helperText: 'Dipakai untuk menghitung estimasi selesai',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minQty,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Minimum',
                        helperText: 'Contoh: 3',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _rounding,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Pembulatan',
                        helperText: 'Contoh: 0,1',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _expressMultiplier,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Pengali express',
                        helperText: 'Contoh: 2',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _expressDuration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Durasi express',
                        helperText: 'jam',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Simpan'),
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
