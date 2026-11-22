import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/db/app_database.dart';

class OrderPhoto {
  const OrderPhoto({
    required this.id,
    required this.orderId,
    required this.path,
    required this.createdAt,
  });

  final int id;
  final int orderId;
  final String path;
  final DateTime createdAt;

  factory OrderPhoto.fromMap(Map<String, Object?> m) => OrderPhoto(
        id: m['id'] as int,
        orderId: m['order_id'] as int,
        path: m['path'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  File get file => File(path);
}

/// Foto cucian saat diterima.
///
/// Sengketa "baju saya hilang" dan "ini sudah sobek sebelum dicuci" adalah
/// masalah paling mahal di usaha laundry, dan satu-satunya yang tidak bisa
/// diselesaikan dengan catatan angka.
class OrderPhotoService {
  OrderPhotoService(this._db);

  final AppDatabase _db;

  final _picker = ImagePicker();

  /// Lebih dari ini hanya menghabiskan ruang HP tanpa menambah bukti.
  static const maxPerOrder = 4;

  /// Sisi terpanjang foto setelah diperkecil.
  ///
  /// 1280 piksel cukup untuk memperlihatkan noda dan sobekan, dan menahan
  /// berkasnya di sekitar 150 KB. Foto asli kamera HP sekarang bisa 4 MB
  /// sekali jepret; seratus order sebulan berarti setengah giga, di HP yang
  /// penyimpanannya memang sudah sempit.
  static const _maxEdge = 1280;

  Future<List<OrderPhoto>> of(int orderId) async {
    final db = await _db.database;
    final rows = await db.query(
      'order_photos',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at',
    );
    return rows.map(OrderPhoto.fromMap).toList();
  }

  Future<int> countOf(int orderId) async => (await of(orderId)).length;

  /// Memotret dan menyimpan. Mengembalikan null bila pengguna membatalkan.
  Future<OrderPhoto?> capture(
    int orderId, {
    ImageSource source = ImageSource.camera,
  }) async {
    // Manifes aplikasi menyebut izin CAMERA karena pemindai QR
    // membutuhkannya. Begitu izin itu disebut, Android mewajibkan
    // permintaan saat berjalan sebelum kamera bisa dibuka sama sekali.
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw Exception(
          'Izin kamera ditolak. Nyalakan di setelan aplikasi untuk '
          'memotret cucian.',
        );
      }
    }

    final shot = await _picker.pickImage(
      source: source,
      // Dikecilkan sejak di kamera supaya memori tidak melonjak di HP
      // kelas bawah sebelum sempat dikecilkan sendiri.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (shot == null) return null;

    final bytes = await shot.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final resized = decoded.width > decoded.height
        ? img.copyResize(decoded, width: _maxEdge)
        : img.copyResize(decoded, height: _maxEdge);

    final dir = await _photoDir();
    final now = DateTime.now();
    final file = File(
      '${dir.path}/order_${orderId}_${now.millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(resized, quality: 80));

    final db = await _db.database;
    final id = await db.insert('order_photos', {
      'order_id': orderId,
      'path': file.path,
      'created_at': now.toIso8601String(),
    });

    return OrderPhoto(
      id: id,
      orderId: orderId,
      path: file.path,
      createdAt: now,
    );
  }

  /// Menghapus catatan lebih dulu, baru berkasnya.
  ///
  /// Urutan ini disengaja: berkas yatim hanya memakan ruang, sedangkan
  /// catatan yang menunjuk berkas hilang membuat layar detail gagal
  /// digambar.
  Future<void> delete(OrderPhoto photo) async {
    final db = await _db.database;
    await db.delete('order_photos', where: 'id = ?', whereArgs: [photo.id]);

    try {
      if (await photo.file.exists()) await photo.file.delete();
    } catch (_) {
      // Berkas yang gagal dihapus bukan alasan untuk menggagalkan aksi
      // pengguna. Catatannya sudah hilang, dan itu yang terlihat.
    }
  }

  Future<Directory> _photoDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/order_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
