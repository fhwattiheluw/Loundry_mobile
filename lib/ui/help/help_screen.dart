import 'package:material_ui/material_ui.dart';

import '../../core/design_system.dart';
import '../widgets/layout.dart';

/// Panduan singkat di dalam aplikasi.
///
/// Pemilik warung laundry jarang membaca petunjuk di luar aplikasi, dan
/// pertanyaan yang sama selalu muncul: cara cetak nota, kenapa ada iklan,
/// apa yang terjadi bila HP hilang. Jawabannya ditaruh di sini, dengan
/// kata-kata yang sama dengan yang tertulis di layar lain.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            context.screenPadding,
            AppSpacing.sm,
            context.screenPadding,
            AppSpacing.xxxl,
          ),
          children: [
            for (final section in _sections) ...[
              SectionHeader(section.title),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < section.topics.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _TopicTile(topic: section.topics[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: IconBadge(topic.icon, tone: topic.tone),
      title: Text(topic.question, style: theme.textTheme.titleSmall),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < topic.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    topic.numbered ? '${i + 1}.' : '•',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: Text(topic.steps[i], style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class HelpTopic {
  const HelpTopic({
    required this.icon,
    required this.tone,
    required this.question,
    required this.steps,
    this.numbered = true,
  });

  final IconData icon;
  final int tone;
  final String question;
  final List<String> steps;

  /// Langkah berurutan diberi nomor. Penjelasan lepas diberi titik.
  final bool numbered;
}

class _Section {
  const _Section(this.title, this.topics);

  final String title;
  final List<HelpTopic> topics;
}

const _sections = [
  _Section('Sehari-hari', [
    HelpTopic(
      icon: Icons.add_circle_outline,
      tone: 0,
      question: 'Cara membuat order baru',
      steps: [
        'Di Beranda atau tab Order, tekan tombol Order Baru.',
        'Isi nama pelanggan. Nomor WhatsApp boleh dikosongkan. Pelanggan '
            'lama bisa dicari dengan tombol kaca pembesar.',
        'Di bagian Layanan, tekan Tambah, pilih layanan, lalu isi berat '
            'atau jumlahnya.',
        'Bila pelanggan membayar di muka, isi kolom Dibayar.',
        'Tekan Simpan & Cetak Nota.',
      ],
    ),
    HelpTopic(
      icon: Icons.local_laundry_service_outlined,
      tone: 1,
      question: 'Cara mengubah status cucian',
      steps: [
        'Buka order dari tab Order, lalu tekan tombol di dasar layar yang '
            'bertuliskan status berikutnya, misalnya Diproses.',
        'Alurnya Diterima, Diproses, Selesai, lalu Diambil. Pelanggan '
            'dikabari lewat WhatsApp sesuai pengaturan notifikasi.',
        'Beberapa order sekaligus: tekan lama satu order di daftar, pilih '
            'yang lain, lalu tandai di bagian atas layar.',
        'Order yang sudah Dibatalkan tidak bisa diubah lagi, jadi pastikan '
            'sebelum membatalkan.',
      ],
    ),
    HelpTopic(
      icon: Icons.search,
      tone: 2,
      question: 'Cara mencari order lama',
      steps: [
        'Di tab Order, ketik nomor nota, nama, atau nomor HP di kolom cari.',
        'Atau tekan ikon pindai QR dan arahkan kamera ke kode di nota '
            'pelanggan. Langsung terbuka orderannya.',
        'Tombol bulat di bawah kolom cari menyaring daftar, misalnya hanya '
            'yang Selesai atau yang Belum lunas.',
      ],
      numbered: false,
    ),
    HelpTopic(
      icon: Icons.account_balance_wallet_outlined,
      tone: 4,
      question: 'Pelanggan belum lunas, bagaimana mencatatnya?',
      steps: [
        'Simpan order seperti biasa. Kolom Dibayar boleh kurang dari total '
            'atau kosong.',
        'Saat pelanggan melunasi, buka ordernya dan tekan Bayar.',
        'Semua yang belum lunas terkumpul di Beranda, menu Piutang, '
            'diurutkan dari yang paling lama.',
      ],
    ),
  ]),
  _Section('Pengaturan', [
    HelpTopic(
      icon: Icons.print_outlined,
      tone: 3,
      question: 'Printer tidak muncul atau nota tidak tercetak',
      steps: [
        'Nyalakan printer, lalu pasangkan dulu lewat Pengaturan Bluetooth '
            'di HP.',
        'Di aplikasi, buka Pengaturan, Printer Bluetooth, lalu pilih '
            'printernya.',
        'Pilih lebar kertas yang sama dengan gulungan di printer, 58 mm '
            'atau 80 mm.',
        'Order tetap tersimpan walau nota gagal tercetak. Nota bisa '
            'dicetak ulang dari halaman order.',
      ],
    ),
    HelpTopic(
      icon: Icons.local_offer_outlined,
      tone: 5,
      question: 'Mengubah layanan dan harga',
      steps: [
        'Pengaturan, Layanan dan harga (hanya Owner).',
        'Tekan Layanan baru, atau ketuk layanan yang ada untuk mengubahnya.',
        'Layanan tidak dihapus, hanya disembunyikan dari pilihan kasir, '
            'sehingga nota lama tetap utuh. Tombol Urungkan muncul sesaat '
            'setelah menyembunyikan.',
      ],
    ),
    HelpTopic(
      icon: Icons.point_of_sale_outlined,
      tone: 6,
      question: 'Apa gunanya shift kasir?',
      steps: [
        'Shift mencatat uang tunai di laci. Buka shift di awal hari dan '
            'isi uang yang ada di laci.',
        'Selama shift berjalan, pembayaran tunai ikut terhitung.',
        'Saat tutup shift, hitung uang di laci dan masukkan. Aplikasi '
            'menunjukkan selisihnya bila ada.',
        'Tanpa shift terbuka, pembayaran tetap tersimpan tetapi tidak '
            'masuk hitungan kas laci.',
      ],
      numbered: false,
    ),
    HelpTopic(
      icon: Icons.send_outlined,
      tone: 8,
      question: 'Pesan WhatsApp ke pelanggan',
      steps: [
        'Mode manual: aplikasi membuka WhatsApp dengan pesan yang sudah '
            'terisi, dan kasir tinggal menekan kirim.',
        'Mode otomatis butuh akun WhatsApp Cloud API milik Anda sendiri. '
            'Atur di Pengaturan, Mode pengiriman.',
        'Pesan yang gagal terkirim menunggu di Pesan belum terkirim dan '
            'dicoba lagi saat internet kembali.',
      ],
      numbered: false,
    ),
  ]),
  _Section('Data dan keamanan', [
    HelpTopic(
      icon: Icons.backup_outlined,
      tone: 11,
      question: 'Kenapa harus backup, dan bagaimana caranya?',
      steps: [
        'Semua data tersimpan hanya di HP ini, tidak di internet. Bila HP '
            'hilang, rusak, atau di-reset, data ikut hilang.',
        'Buka Pengaturan, Backup dan restore, lalu tekan Buka wizard '
            'backup.',
        'Pilih Bagikan ke luar HP untuk mengirim berkas ke WhatsApp atau '
            'Google Drive Anda sendiri, atau Simpan di HP ini saja.',
        'Aplikasi mengingatkan setiap minggu. Simpan berkas di tempat lain '
            'selain HP ini supaya benar-benar aman.',
      ],
    ),
    HelpTopic(
      icon: Icons.settings_backup_restore,
      tone: 12,
      question: 'Pindah ke HP baru atau data hilang',
      steps: [
        'Pasang aplikasi di HP baru dan lewati pengaturan awal.',
        'Pindahkan berkas backup ke HP baru.',
        'Buka Pengaturan, Backup dan restore, lalu tekan Kembalikan dari '
            'berkas backup.',
      ],
    ),
    HelpTopic(
      icon: Icons.lock_outline,
      tone: 9,
      question: 'Lupa PIN atau PIN terkunci',
      steps: [
        'Salah PIN lima kali berturut-turut mengunci layar masuk sementara. '
            'Tunggu hingga hitungan mundur selesai.',
        'Pemilik yang lupa PIN menekan Lupa PIN pemilik di layar masuk, '
            'lalu memakai kode lewat WhatsApp atau kode pemulihan yang '
            'dicatat saat pengaturan awal.',
        'Kasir yang lupa PIN meminta Owner menggantinya di Pengaturan, '
            'Pengguna dan PIN.',
      ],
    ),
  ]),
  _Section('Tentang aplikasi', [
    HelpTopic(
      icon: Icons.ads_click,
      tone: 2,
      question: 'Kenapa ada iklan?',
      steps: [
        'Laundry Manise gratis sepenuhnya. Iklan adalah satu-satunya '
            'sumber biaya pengembangan.',
        'Iklan tidak pernah muncul di layar mengisi order atau pembayaran, '
            'supaya tidak mengganggu kasir yang sedang melayani.',
      ],
      numbered: false,
    ),
    HelpTopic(
      icon: Icons.wifi,
      tone: 1,
      question: 'Kenapa butuh internet?',
      steps: [
        'Internet dipakai untuk memuat iklan dan mengirim pesan WhatsApp.',
        'Data usaha Anda tetap disimpan di HP. Bila internet mati '
            'sebentar, order dan pembayaran tetap bisa dicatat seperti biasa.',
      ],
      numbered: false,
    ),
  ]),
];
