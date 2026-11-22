import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

final _plainNumber = NumberFormat.decimalPattern('id_ID');
final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
final _dateOnly = DateFormat('dd/MM/yyyy', 'id_ID');
final _dayMonth = DateFormat('d MMM', 'id_ID');
final _longDate = DateFormat('EEEE, d MMMM yyyy', 'id_ID');

String formatRupiah(int value) => _rupiah.format(value);

/// Untuk nota thermal: tanpa simbol, karena banyak printer murah
/// menampilkan "Rp" dan karakter non-ASCII lain sebagai sampah.
String formatPlain(int value) => _plainNumber.format(value);

String formatDateTime(DateTime value) => _dateTime.format(value);

String formatDate(DateTime value) => _dateOnly.format(value);

String formatDayMonth(DateTime value) => _dayMonth.format(value);

String formatLongDate(DateTime value) => _longDate.format(value);

/// 3.0 -> "3", 3.5 -> "3,5". Berat ditulis tanpa nol ekor yang tidak berguna.
String formatQty(double qty) {
  if (qty == qty.roundToDouble()) return qty.toInt().toString();
  return qty.toString().replaceAll('.', ',');
}

/// Mengubah teks yang diketik kasir menjadi angka rupiah.
/// "25.000" dan "25000" sama-sama menghasilkan 25000.
int parseRupiah(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : int.parse(digits);
}

/// "3,4" dan "3.4" sama-sama menghasilkan 3.4.
double parseQty(String input) {
  final cleaned = input.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(cleaned) ?? 0;
}

/// Selisih hari kalender, bukan selisih 24 jam.
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String relativeDays(DateTime from, DateTime to) {
  final days = daysBetween(from, to);
  if (days == 0) return 'hari ini';
  if (days == 1) return 'kemarin';
  return '$days hari lalu';
}


/// Memberi titik ribuan sambil kasir mengetik: 10000 tampil sebagai 10.000.
///
/// Angka uang tanpa pemisah mudah salah dibaca satu digit, dan satu digit
/// pada harga laundry adalah selisih sepuluh kali. Kursor selalu pindah ke
/// ujung kanan, karena menyisipkan digit di tengah angka uang hampir selalu
/// kekeliruan, bukan niat.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return const TextEditingValue();

    // Lebih dari dua belas digit bukan harga laundry, dan int.parse bisa
    // melimpah. Ketikan itu ditolak, isian lama dipertahankan.
    if (digits.length > 12) return oldValue;

    final text = formatPlain(int.parse(digits));

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Dipakai di setiap kolom uang, supaya tidak ada satu layar pun yang
/// menampilkan 10000 sementara layar lain menampilkan 10.000.
const rupiahInputFormatters = <TextInputFormatter>[RupiahInputFormatter()];
