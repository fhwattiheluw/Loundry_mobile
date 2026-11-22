import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system.dart';
import '../../core/formatters.dart';

/// Papan angka besar untuk memasukkan berat dan nominal uang.
///
/// Papan ketik bawaan Android menampilkan angka setinggi sekitar 20 dp dan
/// menutupi separuh layar. Di konter, kasir memasukkan berat sambil
/// memegang timbangan dan melayani pelanggan. Papan ini tombolnya 64 dp,
/// tidak menutupi angka yang sedang diketik, dan punya pintasan nominal
/// yang paling sering dipakai.
class NumberPad extends StatefulWidget {
  const NumberPad({
    super.key,
    required this.onSubmit,
    this.initialValue = '',
    this.allowDecimal = false,
    this.title,
    this.unit,
    this.quickValues = const [],
    this.isMoney = false,
    this.submitLabel = 'Simpan',
    this.helper,
  });

  final void Function(String value) onSubmit;
  final String initialValue;

  /// Berat boleh pecahan, jumlah potong tidak.
  final bool allowDecimal;
  final String? title;
  final String? unit;

  /// Pintasan nominal, misalnya 50.000 dan 100.000 untuk uang tunai.
  final List<int> quickValues;
  final bool isMoney;
  final String submitLabel;
  final String? helper;

  @override
  State<NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<NumberPad> {
  late String _value = widget.initialValue;

  bool get _hasValue => _value.isNotEmpty && double.tryParse(_raw) != null;

  String get _raw => _value.replaceAll(',', '.');

  void _tap(String key) {
    HapticFeedback.selectionClick();

    setState(() {
      if (key == ',') {
        // Hanya satu koma, dan selalu didahului angka.
        if (_value.contains(',')) return;
        _value = _value.isEmpty ? '0,' : '$_value,';
        return;
      }

      // Nol di depan tidak berguna: "007" bukan angka yang ditulis orang.
      if (_value == '0' && key != ',') {
        _value = key;
        return;
      }

      if (_value.length >= 9) return;
      _value += key;
    });
  }

  void _backspace() {
    if (_value.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  void _clear() {
    HapticFeedback.mediumImpact();
    setState(() => _value = '');
  }

  void _addQuick(int amount) {
    HapticFeedback.selectionClick();
    final current = parseRupiah(_value);
    setState(() => _value = (current + amount).toString());
  }

  String get _display {
    if (_value.isEmpty) return '0';
    if (widget.isMoney) return formatPlain(parseRupiah(_value));
    return _value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: Text(widget.title!, style: theme.textTheme.titleMedium),
          ),

        // Angka yang sedang diketik, sebesar mungkin.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (widget.isMoney)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text('Rp', style: theme.textTheme.titleMedium),
                ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _display,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 40,
                      color: _hasValue
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              if (widget.unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Text(
                    widget.unit!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(widget.helper!, style: theme.textTheme.bodySmall),
          ),

        if (widget.quickValues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: SizedBox(
              height: AppTouch.minimum,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.quickValues.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final amount = widget.quickValues[i];
                  return ActionChip(
                    label: Text('+ ${formatPlain(amount)}'),
                    onPressed: () => _addQuick(amount),
                  );
                },
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(
                  children: [
                    for (final key in row)
                      Expanded(child: _Key(label: key, onTap: () => _tap(key))),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: widget.allowDecimal
                        ? _Key(label: ',', onTap: () => _tap(','))
                        : _Key(
                            label: '000',
                            onTap: () {
                              if (_value.isEmpty) return;
                              _tap('0');
                              _tap('0');
                              _tap('0');
                            },
                          ),
                  ),
                  Expanded(child: _Key(label: '0', onTap: () => _tap('0'))),
                  Expanded(
                    child: _Key(
                      icon: Icons.backspace_outlined,
                      onTap: _backspace,
                      onLongPress: _clear,
                      semanticLabel: 'Hapus satu angka, tekan lama untuk kosongkan',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: FilledButton(
            onPressed: _hasValue
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onSubmit(_value);
                  }
                : null,
            child: Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Semantics(
        label: semanticLabel,
        button: true,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: AppTouch.primary,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 24)
                    : Text(
                        label!,
                        style: theme.textTheme.displaySmall
                            ?.copyWith(fontSize: 24),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Membuka papan angka sebagai lembar bawah dan mengembalikan hasilnya.
Future<String?> showNumberPad(
  BuildContext context, {
  String? title,
  String initialValue = '',
  bool allowDecimal = false,
  String? unit,
  List<int> quickValues = const [],
  bool isMoney = false,
  String submitLabel = 'Simpan',
  String? helper,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: NumberPad(
          title: title,
          initialValue: initialValue,
          allowDecimal: allowDecimal,
          unit: unit,
          quickValues: quickValues,
          isMoney: isMoney,
          submitLabel: submitLabel,
          helper: helper,
          onSubmit: (value) => Navigator.pop(context, value),
        ),
      ),
    ),
  );
}
