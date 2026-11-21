import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers.dart';
import 'core/theme.dart';
import 'services/connectivity/connection_guard.dart';
import 'ui/auth/pin_login_screen.dart';
import 'ui/home/home_shell.dart';

class LaundryPosApp extends ConsumerWidget {
  const LaundryPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'POS Laundry',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Gerbang internet membungkus seluruh aplikasi. Layar apa pun hanya
      // tergambar setelah koneksi terbukti ada.
      home: const ConnectionGate(child: _Root()),
    );
  }
}

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
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Database gagal dibuka.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.invalidate(settingsLoadedProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
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
