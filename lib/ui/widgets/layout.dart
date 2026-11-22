import 'package:flutter/material.dart';

import '../../core/design_system.dart';

/// Membatasi lebar isi di layar lebar.
///
/// Tanpa batas ini, satu baris teks di tablet mendatar bisa selebar 1200 px,
/// dan mata kehilangan awal baris berikutnya. Enam puluh sampai tujuh puluh
/// karakter per baris adalah batas yang nyaman dibaca.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Daftar yang berubah jadi kisi di layar lebar.
///
/// Di HP tetap satu kolom supaya kartu order lebar dan mudah ditekan.
/// Di tablet jadi dua atau tiga kolom, sehingga kasir melihat lebih banyak
/// order tanpa menggulir.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.spacing = AppSpacing.md,
    this.maxColumns = 3,
    this.minItemWidth = 320,
  });

  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double spacing;
  final int maxColumns;

  /// Lebar minimum satu kartu. Kolom ditambah hanya bila setiap kartu
  /// masih mendapat lebar ini.
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth;
        final columns = (usable / minItemWidth).floor().clamp(1, maxColumns);

        if (columns == 1) {
          return ListView.separated(
            padding: padding,
            itemCount: itemCount,
            separatorBuilder: (_, __) => SizedBox(height: spacing),
            itemBuilder: itemBuilder,
          );
        }

        // Kartu order tingginya berbeda-beda, jadi kisi dibuat dari deretan
        // Row, bukan GridView. GridView memaksa semua sel setinggi sel
        // tertinggi, dan itu meninggalkan ruang kosong yang mencolok.
        final rows = (itemCount / columns).ceil();

        return ListView.separated(
          padding: padding,
          itemCount: rows,
          separatorBuilder: (_, __) => SizedBox(height: spacing),
          itemBuilder: (context, row) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) SizedBox(width: spacing),
                    Expanded(
                      child: row * columns + col < itemCount
                          ? itemBuilder(context, row * columns + col)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Dua kotak angka sebaris di HP, empat sebaris di tablet.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final columns = context.isWide ? 4 : 2;
    final rows = (children.length / columns).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: row * columns + col < children.length
                        ? children[row * columns + col]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Judul bagian dengan jarak yang seragam.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
