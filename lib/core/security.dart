import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PIN tidak pernah disimpan sebagai teks asli.
///
/// Catatan jujur: SHA-256 dengan garam tetap TIDAK cukup kuat untuk kata sandi
/// bernilai tinggi. Untuk PIN 4 digit yang hanya melindungi akses di perangkat
/// konter, ini sepadan. Jika nanti ada akun daring, ganti ke Argon2 atau bcrypt.
const _salt = 'laundry_pos.v1';

String hashPin(String pin) {
  final bytes = utf8.encode('$_salt:$pin');
  return sha256.convert(bytes).toString();
}

bool verifyPin(String pin, String hash) => hashPin(pin) == hash;

/// Normalisasi nomor HP Indonesia ke format internasional tanpa tanda plus.
///
/// 0812-3456-7890 -> 6281234567890
/// +62 812 3456 7890 -> 6281234567890
/// 62812... -> tetap
String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');

  if (digits.startsWith('+')) digits = digits.substring(1);
  if (digits.startsWith('0')) return '62${digits.substring(1)}';
  if (digits.startsWith('62')) return digits;
  if (digits.startsWith('8')) return '62$digits';

  return digits;
}

/// Benar untuk nomor seluler Indonesia yang masuk akal: 62 diikuti 8
/// dan total 10 sampai 15 digit.
bool isValidPhone(String raw) {
  final normalized = normalizePhone(raw);
  return RegExp(r'^628[0-9]{7,12}$').hasMatch(normalized);
}

/// Tampilan yang enak dibaca di layar: 0812-3456-7890
String prettyPhone(String stored) {
  if (!stored.startsWith('62')) return stored;
  final local = '0${stored.substring(2)}';
  if (local.length < 8) return local;

  final head = local.substring(0, 4);
  final middle = local.substring(4, local.length > 8 ? 8 : local.length);
  final tail = local.length > 8 ? local.substring(8) : '';

  return tail.isEmpty ? '$head-$middle' : '$head-$middle-$tail';
}
