import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

/// Pembelian sekali bayar untuk menghilangkan iklan (FR-118).
///
/// Untuk aplikasi POS, ini biasanya lebih masuk akal daripada iklan itu
/// sendiri: pemilik yang terganggu iklan di depan pelanggan akan membayar
/// sekali, dan itu nilainya jauh di atas pendapatan iklan berbulan-bulan
/// dari satu perangkat.
class PurchaseService {
  PurchaseService(this._settings);

  final SettingsRepository _settings;

  static const productId = 'remove_ads';

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  ProductDetails? _product;
  bool _available = false;

  bool get isAvailable => _available;
  ProductDetails? get product => _product;

  /// Harga yang sudah diformat toko, misalnya "Rp 49.000".
  /// Selalu pakai nilai dari Play Store, jangan tulis harga di kode:
  /// mata uang dan pajak berbeda per negara.
  String get priceLabel => _product?.price ?? '';

  bool get adsRemoved => _settings.getBool(SettingsKeys.adsRemoved);

  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;

      final response = await _iap.queryProductDetails({productId});
      if (response.productDetails.isNotEmpty) {
        _product = response.productDetails.first;
      }

      // Pembelian lama dikabarkan lewat aliran pembelian, jadi pemulihan
      // dipanggil tiap kali aplikasi dibuka. Tanpa ini, pemilik yang sudah
      // membayar akan melihat iklan lagi setelah pasang ulang.
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
      if (purchase.productID != productId) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _settings.set(SettingsKeys.adsRemoved, '1');

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
