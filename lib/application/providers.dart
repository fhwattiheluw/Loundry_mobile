import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/db/settings_keys.dart';
import '../data/repositories/master_repository.dart';
import '../data/repositories/order_repository.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/shift_repository.dart';
import '../domain/models/models.dart';
import '../domain/price_calculator.dart';
import '../services/license/license_service.dart';
import '../services/ads/ad_service.dart';
import '../services/ads/consent_manager.dart';
import '../services/ads/purchase_service.dart';
import '../services/backup/backup_service.dart';
import '../services/export/export_service.dart';
import '../services/notification/message_template.dart';
import '../services/notification/notification_service.dart';
import '../services/notification/whatsapp_api_sender.dart';
import '../services/printer/receipt_builder.dart';
import '../services/printer/receipt_printer.dart';

// ------------------------------------------------------------------- dasar

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final calculatorProvider = Provider<PriceCalculator>(
  (ref) => const PriceCalculator(),
);

final settingsRepoProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

/// Pengaturan dimuat sekali di awal, lalu dipakai banyak layar.
final settingsLoadedProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(settingsRepoProvider).loadAll(),
);

// ------------------------------------------------------------------- data

final customerRepoProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(databaseProvider)),
);

final serviceRepoProvider = Provider<ServiceRepository>(
  (ref) => ServiceRepository(ref.watch(databaseProvider)),
);

final userRepoProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(databaseProvider)),
);

final orderRepoProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(
    ref.watch(databaseProvider),
    calculator: ref.watch(calculatorProvider),
  ),
);

final reportRepoProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(databaseProvider)),
);

final shiftRepoProvider = Provider<ShiftRepository>(
  (ref) => ShiftRepository(ref.watch(databaseProvider)),
);

/// Shift yang sedang terbuka untuk pengguna yang login.
/// Null berarti kasir belum membuka shift.
final currentShiftProvider = FutureProvider<Shift?>((ref) async {
  final user = ref.watch(sessionProvider);
  if (user == null) return null;
  return ref.watch(shiftRepoProvider).openShiftOf(user.id!);
});

final shiftTotalsProvider = FutureProvider<ShiftTotals>((ref) async {
  final shift = await ref.watch(currentShiftProvider.future);
  if (shift == null) return ShiftTotals.empty;
  return ref.watch(shiftRepoProvider).totalsOf(shift);
});

// --------------------------------------------------------------- layanan

final printerProvider = Provider<ReceiptPrinter>(
  (ref) => ReceiptPrinter(ref.watch(settingsRepoProvider)),
);

final receiptBuilderProvider = Provider<ReceiptBuilder>(
  (ref) => ReceiptBuilder(ref.watch(settingsRepoProvider)),
);

final messageTemplateProvider = Provider<MessageTemplate>(
  (ref) => MessageTemplate(ref.watch(settingsRepoProvider)),
);

final whatsAppApiSenderProvider = Provider<WhatsAppApiSender>(
  (ref) => WhatsAppApiSender(ref.watch(settingsRepoProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(
    db: ref.watch(databaseProvider),
    template: ref.watch(messageTemplateProvider),
    settings: ref.watch(settingsRepoProvider),
    manualSender: const WhatsAppManualSender(),
    apiSender: ref.watch(whatsAppApiSenderProvider),
  ),
);

/// Pengirim untuk promo broadcast, mengikuti mode yang dipilih pemilik.
/// Promo tidak lewat NotificationService karena tidak terikat ke satu order
/// dan tidak perlu masuk log per-order.
final broadcastSenderProvider = Provider<NotificationSender>((ref) {
  final settings = ref.watch(settingsRepoProvider);
  final isApi =
      settings.get(SettingsKeys.whatsappMode, fallback: 'manual') == 'api';

  return isApi
      ? ref.watch(whatsAppApiSenderProvider)
      : const WhatsAppManualSender();
});

/// Jumlah pesan yang masih menunggu giliran kirim.
final pendingNotificationsProvider = FutureProvider<int>(
  (ref) => ref.watch(notificationServiceProvider).pendingCount(),
);

final licenseServiceProvider = Provider<LicenseService>(
  (ref) => LicenseService(ref.watch(settingsRepoProvider)),
);

/// Dibaca ulang setiap kali layar langganan perlu menggambar keadaan baru.
final licenseStatusProvider = StateProvider<LicenseStatus>(
  (ref) => ref.watch(licenseServiceProvider).status,
);

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(
    ref.watch(settingsRepoProvider),
    ref.watch(licenseServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentManagerProvider = Provider<ConsentManager>(
  (ref) => ConsentManager(),
);

final adServiceProvider = Provider<AdService>(
  (ref) => AdService(
    ref.watch(settingsRepoProvider),
    ref.watch(consentManagerProvider),
  ),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => const ExportService(),
);

// --------------------------------------------------------------- sesi

/// Pengguna yang sedang login. Null berarti layar PIN.
class SessionController extends StateNotifier<AppUser?> {
  SessionController() : super(null);

  void signIn(AppUser user) => state = user;
  void signOut() => state = null;
}

final sessionProvider =
    StateNotifierProvider<SessionController, AppUser?>((ref) => SessionController());

final currentUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(sessionProvider);
  if (user == null) {
    throw StateError('Layar ini hanya boleh dibuka setelah login.');
  }
  return user;
});

// --------------------------------------------------------------- daftar

final servicesProvider = FutureProvider<List<LaundryService>>(
  (ref) => ref.watch(serviceRepoProvider).all(),
);

final orderFilterProvider = StateProvider<OrderFilter>(
  (ref) => const OrderFilter(),
);

final orderListProvider = FutureProvider<List<LaundryOrder>>((ref) {
  final filter = ref.watch(orderFilterProvider);
  return ref.watch(orderRepoProvider).find(filter);
});

final orderDetailProvider =
    FutureProvider.family<LaundryOrder?, int>((ref, id) {
  return ref.watch(orderRepoProvider).byId(id);
});

/// Order selesai yang sudah lewat batas hari dan belum diambil.
final staleOrdersProvider = FutureProvider<List<LaundryOrder>>((ref) async {
  await ref.watch(settingsLoadedProvider.future);
  final days = ref.watch(settingsRepoProvider).getInt('reminder_days', fallback: 3);
  return ref.watch(orderRepoProvider).staleOrders(days);
});

// --------------------------------------------------------------- laporan

class ReportRange {
  const ReportRange(this.from, this.to, this.label);

  final DateTime from;
  final DateTime to;
  final String label;

  static ReportRange today() {
    final now = DateTime.now();
    return ReportRange(now, now, 'Hari ini');
  }

  static ReportRange thisWeek() {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    return ReportRange(start, now, 'Minggu ini');
  }

  static ReportRange thisMonth() {
    final now = DateTime.now();
    return ReportRange(DateTime(now.year, now.month, 1), now, 'Bulan ini');
  }

  static ReportRange lastMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, 0);
    return ReportRange(start, end, 'Bulan lalu');
  }
}

final reportRangeProvider =
    StateProvider<ReportRange>((ref) => ReportRange.today());

final revenueSummaryProvider = FutureProvider<RevenueSummary>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).summary(range.from, range.to);
});

final dailyRevenueProvider = FutureProvider<List<DailyRevenue>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).dailyRevenue(range.from, range.to);
});

final revenueByServiceProvider = FutureProvider<List<NamedAmount>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).byService(range.from, range.to);
});

final revenueByMethodProvider = FutureProvider<List<NamedAmount>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).byMethod(range.from, range.to);
});

final revenueByCashierProvider = FutureProvider<List<NamedAmount>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).byCashier(range.from, range.to);
});

final receivablesProvider = FutureProvider<List<ReceivableRow>>(
  (ref) => ref.watch(reportRepoProvider).receivables(),
);

final topCustomersProvider = FutureProvider<List<NamedAmount>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).topCustomers(range.from, range.to);
});

final previousPeriodProvider = FutureProvider<RevenueSummary>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(reportRepoProvider).previousPeriod(range.from, range.to);
});

/// Dipanggil setiap kali ada perubahan data supaya layar lain ikut segar.
///
/// Satu tempat saja, supaya tidak ada layar yang lupa menyegarkan laporan
/// setelah pembayaran masuk.
extension RefreshData on WidgetRef {
  void refreshOrderData() {
    invalidate(orderListProvider);
    invalidate(staleOrdersProvider);
    invalidate(revenueSummaryProvider);
    invalidate(dailyRevenueProvider);
    invalidate(revenueByServiceProvider);
    invalidate(revenueByMethodProvider);
    invalidate(revenueByCashierProvider);
    invalidate(receivablesProvider);
    invalidate(topCustomersProvider);
    invalidate(previousPeriodProvider);
    invalidate(shiftTotalsProvider);
  }
}
