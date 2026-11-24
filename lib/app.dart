import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers.dart';
import 'core/design_system.dart';
import 'core/theme.dart';
import 'data/db/settings_keys.dart';
import 'services/connectivity/connection_guard.dart';
import 'ui/auth/pin_login_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/onboarding/setup_wizard.dart';
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
          // Gerbang internet membungkus Navigator, bukan hanya halaman
          // pertama, supaya layar luring menutupi semua halaman yang
          // terbuka tanpa membongkarnya. Lihat ConnectionGate.
          child: ConnectionGate(requireInternet: true, child: child!),
        );
      },
      // Gerbang internet (di builder di atas) membungkus seluruh aplikasi.
      // Layar apa pun hanya tergambar setelah koneksi terbukti ada.
      // Aplikasi ini gratis dan hidup dari iklan, dan iklan hanya bisa
      // dimuat saat ada internet. Pemakaian luring berarti pemakaian yang
      // tidak menghasilkan apa pun, jadi internet diwajibkan.
      //
      // Harganya nyata: konter yang sinyalnya mati tidak bisa menerima
      // cucian sama sekali. Bila ternyata itu terlalu mahal di lapangan,
      // requireInternet di builder mengembalikannya - seluruh lapisan data
      // aplikasi tetap sanggup bekerja tanpa internet.
      home: const _Root(),
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
        // Aman dipanggil berulang kali.
        ref.read(adServiceProvider).init();

        // Pemasangan baru: pemilik belum punya PIN, jadi tidak ada yang bisa
        // dimasukkan di layar masuk. Wizard dulu (nama usaha, harga, printer,
        // backup), dan PIN dibuat di langkah terakhirnya. Menunggu data
        // dibaca dulu supaya layar masuk tidak sempat berkedip.
        final firstRun = ref.watch(firstRunProvider);
        if (firstRun.isLoading && !firstRun.hasValue) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (firstRun.valueOrNull ?? false) return const SetupWizard();

        if (user == null) return const PinLoginScreen();

        // Pemasangan lama yang belum sempat menyelesaikan wizard (sudah
        // punya PIN) tetap diarahkan ke wizard sesudah masuk. Tanpa itu,
        // toko mendarat di dashboard bernama "Laundry Saya" dengan harga
        // contoh, dan sebagian besar pemilik tidak akan pernah menemukan
        // Pengaturan sendiri.
        final settingsRepo = ref.read(settingsRepoProvider);
        if (!settingsRepo.getBool(SettingsKeys.setupDone)) {
          return const SetupWizard();
        }

        // Tidak ada gerbang berbayar. Aplikasi ini gratis sepenuhnya dan
        // hidup dari iklan: tiap toko yang memakainya tiap hari bernilai
        // lebih sebagai penonton iklan daripada sebagai calon pelanggan
        // yang membayar dan tidak pernah jadi.
        return const HomeShell();
      },
    );
  }
}

/// Jarak tepi layar yang seragam untuk isi yang menggulir.
EdgeInsets screenPadding(BuildContext context, {double bottom = 0}) {
  final side = context.screenPadding;
  return EdgeInsets.fromLTRB(side, AppSpacing.sm, side, bottom + AppSpacing.xxl);
}
