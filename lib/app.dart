import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers.dart';
import 'core/design_system.dart';
import 'core/theme.dart';
import 'data/db/settings_keys.dart';
import 'services/connectivity/connection_guard.dart';
import 'ui/auth/pin_login_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/widgets/states.dart';

class LaundryPosApp extends ConsumerWidget {
  const LaundryPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Laundry Manise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      builder: (context, child) {
        // Batas pembesaran huruf. Pengguna yang memasang ukuran teks
        // sangat besar di Android tetap terlayani, tapi tata letak kasir
        // tidak sampai hancur dan tombol tetap terbaca.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.4,
        );

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child!,
        );
      },
      // Gerbang internet membungkus seluruh aplikasi. Layar apa pun hanya
      // tergambar setelah koneksi terbukti ada.
      home: const ConnectionGate(child: _Root()),
    );
  }
}

/// Mode tampilan yang dipilih pemilik.
final themeModeProvider = Provider<ThemeMode>((ref) {
  // Dibaca setelah pengaturan selesai dimuat, supaya tidak berkedip dari
  // terang ke gelap saat aplikasi dibuka.
  final loaded = ref.watch(settingsLoadedProvider);
  if (!loaded.hasValue) return ThemeMode.system;

  return switch (ref.watch(settingsRepoProvider).get(SettingsKeys.themeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsLoadedProvider);
    final user = ref.watch(sessionProvider);

    return settings.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: ErrorState(
          title: 'Database gagal dibuka',
          message: '$error',
          onRetry: () => ref.invalidate(settingsLoadedProvider),
        ),
      ),
      data: (_) {
        // Inisialisasi iklan berjalan di latar dan tidak menahan layar.
        ref.read(adServiceProvider).init();
        return user == null ? const PinLoginScreen() : const HomeShell();
      },
    );
  }
}

/// Jarak tepi layar yang seragam untuk isi yang menggulir.
EdgeInsets screenPadding(BuildContext context, {double bottom = 0}) {
  final side = context.screenPadding;
  return EdgeInsets.fromLTRB(side, AppSpacing.sm, side, bottom + AppSpacing.xxl);
}
