import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_service.dart';

/// Pembelian sekali bayar untuk menghilangkan iklan (FR-118).
///
/// Untuk aplikasi POS, ini biasanya lebih masuk akal daripada iklan itu
/// sendiri: pemilik yang terganggu iklan di depan pelanggan akan membayar
/// sekali, dan itu nilainya jauh di atas pendapatan iklan berbulan-bulan
/// dari satu perangkat.
class PurchaseService {
  PurchaseService(this._settings, this._license);

  final SettingsRepository _settings;
  final LicenseService _license;

  static const productId = 'remove_ads';

  /// Langganan bulanan. Id ini harus sama persis dengan id produk yang
  /// dibuat di Play Console, kalau tidak Play Store akan bilang produknya
  /// tidak ada dan tombol langganan tidak pernah muncul.
  static const subscriptionId = 'langganan_bulanan';

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  ProductDetails? _product;
  ProductDetails? _subscriptionProduct;
  bool _available = false;

  bool get isAvailable => _available;
  ProductDetails? get product => _product;
  ProductDetails? get subscriptionProduct => _subscriptionProduct;

  /// Harga langganan apa adanya dari Play Store, misalnya "Rp 5.000".
  String get subscriptionPriceLabel => _subscriptionProduct?.price ?? '';

  /// Harga yang sudah diformat toko, misalnya "Rp 49.000".
  /// Selalu pakai nilai dari Play Store, jangan tulis harga di kode:
  /// mata uang dan pajak berbeda per negara.
  String get priceLabel => _product?.price ?? '';

  bool get adsRemoved => _settings.getBool(SettingsKeys.adsRemoved);

  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;

      final response =
          await _iap.queryProductDetails({productId, subscriptionId});
      for (final details in response.productDetails) {
        if (details.id == productId) _product = details;
        if (details.id == subscriptionId) _subscriptionProduct = details;
      }

      // Langganan yang sudah dibeli dikabarkan lewat aliran pembelian,
      // jadi pemulihan dipanggil setiap kali aplikasi dibuka. Inilah yang
      // memperpanjang masa pakai luring di perangkat yang sudah berlangganan.
      await _iap.restorePurchases();

      _subscription = _iap.purchaseStream.listen(
        _handle,
        onError: (Object e) => debugPrint('Aliran pembelian galat: $e'),
      );
    } catch (e) {
      debugPrint('Pembelian dalam aplikasi tidak tersedia: $e');
      _available = false;
    }
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final isSubscription = purchase.productID == subscriptionId;
      if (purchase.productID != productId && !isSubscription) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (isSubscription) {
            await _license.markVerified();
            // Yang berlangganan tidak melihat iklan. Menagih bulanan lalu
            // tetap menayangkan iklan adalah cara tercepat kehilangan
            // pelanggan yang sudah mau membayar.
            await _settings.set(SettingsKeys.adsEnabled, '0');
          } else {
            await _settings.set(SettingsKeys.adsRemoved, '1');
            // Iklan juga dimatikan, supaya efeknya langsung terasa tanpa
            // pemilik perlu mencari sakelarnya sendiri.
            await _settings.set(SettingsKeys.adsEnabled, '0');
          }

        case PurchaseStatus.error:
          debugPrint('Pembelian gagal: ${purchase.error?.message}');

        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }

      // Wajib dipanggil, jika tidak Play Store akan mengembalikan dana
      // pembelian itu setelah tiga hari.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<bool> buy() async {
    final product = _product;
    if (!_available || product == null) return false;

    try {
      // Non-consumable: dibeli sekali dan berlaku selamanya di akun itu.
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      debugPrint('Gagal memulai pembelian: $e');
      return false;
    }
  }

  /// Memulai langganan bulanan.
  ///
  /// Plugin in_app_purchase memakai buyNonConsumable untuk langganan juga;
  /// yang membedakan jenis produknya adalah pengaturan di Play Console,
  /// bukan panggilan di sini.
  Future<bool> subscribe() async {
    final product = _subscriptionProduct;
    if (!_available || product == null) return false;

    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      debugPrint('Gagal memulai langganan: $e');
      return false;
    }
  }

  /// Memulihkan pembelian di perangkat baru atau setelah pasang ulang.
  /// Tanpa ini, pemilik yang ganti ponsel akan merasa dibohongi.
  Future<void> restore() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Gagal memulihkan pembelian: $e');
    }
  }

  void dispose() => _subscription?.cancel();
}
