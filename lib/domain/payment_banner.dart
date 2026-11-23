import 'models/enums.dart';
import 'models/models.dart';

/// Keadaan bayar yang dicetak besar di nota dan ditampilkan di layar.
///
/// Dipisah dari tampilan supaya aturannya satu dan bisa diuji: nota yang
/// dipegang pelanggan wajib menyatakan LUNAS dengan jelas, dan tidak boleh
/// menyatakannya untuk order yang masih punya tagihan.
enum PaymentBanner {
  lunas('LUNAS'),
  belumLunas('BELUM LUNAS'),
  dibatalkan('DIBATALKAN');

  const PaymentBanner(this.text);

  final String text;
}

PaymentBanner paymentBannerOf(LaundryOrder order) {
  if (order.laundryStatus == LaundryStatus.dibatalkan) {
    return PaymentBanner.dibatalkan;
  }
  return order.remaining <= 0 ? PaymentBanner.lunas : PaymentBanner.belumLunas;
}
