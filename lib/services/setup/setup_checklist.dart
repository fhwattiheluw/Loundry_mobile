/// Daftar langkah awal yang membuat aplikasi siap dipakai berjualan.
///
/// Wizard pengaturan awal hanya muncul sekali dan banyak pemilik
/// melewatinya. Daftar ini tetap menunggu di Beranda sampai semua langkah
/// penting selesai, lalu hilang sendiri.
enum SetupStep { business, printer, backup }

class SetupItem {
  const SetupItem({
    required this.step,
    required this.title,
    required this.hint,
    required this.done,
  });

  final SetupStep step;
  final String title;
  final String hint;
  final bool done;
}

class SetupChecklist {
  const SetupChecklist(this.items, {this.hidden = false});

  /// Nama usaha bawaan dari data awal. Selama masih ini, pemilik belum
  /// mengisi nama usahanya sendiri, dan nota akan tercetak "Laundry Saya".
  static const defaultBusinessName = 'Laundry Saya';

  factory SetupChecklist.evaluate({
    required String businessName,
    required String printerName,
    required bool backedUp,
    bool hidden = false,
  }) {
    final name = businessName.trim();

    return SetupChecklist(
      [
        SetupItem(
          step: SetupStep.business,
          title: 'Isi nama dan alamat usaha',
          hint: 'Tercetak di kepala setiap nota.',
          done: name.isNotEmpty && name != defaultBusinessName,
        ),
        SetupItem(
          step: SetupStep.printer,
          title: 'Hubungkan printer nota',
          hint: 'Lewati bila Anda tidak mencetak nota.',
          done: printerName.trim().isNotEmpty,
        ),
        SetupItem(
          step: SetupStep.backup,
          title: 'Buat backup pertama',
          hint: 'Supaya data aman bila HP hilang atau rusak.',
          done: backedUp,
        ),
      ],
      hidden: hidden,
    );
  }

  final List<SetupItem> items;
  final bool hidden;

  int get doneCount => items.where((i) => i.done).length;
  int get total => items.length;
  bool get complete => doneCount == total;

  /// Kartu tampil selama belum disembunyikan dan masih ada yang tersisa.
  bool get visible => !hidden && !complete;
}
