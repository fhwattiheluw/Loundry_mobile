import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Format tanggal Indonesia harus dimuat sebelum layar pertama digambar.
  await initializeDateFormatting('id_ID', null);

  // Semua arah diizinkan. Kunci tegak dibuang karena banyak konter
  // memakai tablet yang dipasang mendatar di dudukan, dan di layar lebar
  // aplikasi memang beralih ke tata letak dua kolom.
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  runApp(const ProviderScope(child: LaundryPosApp()));
}
