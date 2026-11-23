import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/db/settings_keys.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:laundry_pos/services/notification/whatsapp_api_sender.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('parameter template Meta', () {
    test('baris baru disambung menjadi satu baris', () {
      expect(WhatsAppApiSender.templateParam('a\nb'), 'a | b');
      expect(WhatsAppApiSender.templateParam('a\r\nb'), 'a | b');
    });

    test('baris kosong berderet tidak menumpuk pemisah', () {
      expect(WhatsAppApiSender.templateParam('a\n\n\nb'), 'a | b');
      expect(WhatsAppApiSender.templateParam('a   \n   b'), 'a | b');
    });

    test('tab menjadi spasi dan spasi berderet dipadatkan', () {
      expect(WhatsAppApiSender.templateParam('a\tb'), 'a b');
      expect(WhatsAppApiSender.templateParam('a      b'), 'a b');
    });

    test('spasi dan baris baru di ujung tidak meninggalkan pemisah', () {
      expect(WhatsAppApiSender.templateParam('  a\n'), 'a');
    });

    test('rincian nota terbaca sebagai satu kalimat', () {
      const itemLines = '1. Cuci Kiloan\n'
          '   3,5 kg × Rp 7.000 = Rp 24.500\n'
          '   Isi: 3 kemeja';

      expect(
        WhatsAppApiSender.templateParam(itemLines),
        '1. Cuci Kiloan | 3,5 kg × Rp 7.000 = Rp 24.500 | Isi: 3 kemeja',
      );
    });

    test('hasilnya tidak pernah melanggar aturan Meta', () {
      const message = 'Halo Budi\n\nOrder LD-1\n\n1. Cuci Kiloan\n'
          '   3,5 kg × Rp 7.000\n\t*Total: Rp 74.500*\n';

      final out = WhatsAppApiSender.templateParam(message);

      expect(out.contains('\n'), isFalse);
      expect(out.contains('\r'), isFalse);
      expect(out.contains('\t'), isFalse);
      expect(RegExp(r' {5,}').hasMatch(out), isFalse);
    });
  });

  group('versi API', () {
    test('bentuk yang benar diterima, huruf besar dan awalan dibetulkan', () {
      expect(WhatsAppApiSender.normalizeApiVersion('v21.0'), 'v21.0');
      expect(WhatsAppApiSender.normalizeApiVersion('V21.0'), 'v21.0');
      expect(WhatsAppApiSender.normalizeApiVersion('21.0'), 'v21.0');
      expect(WhatsAppApiSender.normalizeApiVersion(' v22.1 '), 'v22.1');
    });

    test('kosong memakai versi bawaan', () {
      expect(WhatsAppApiSender.normalizeApiVersion(''), 'v21.0');
      expect(WhatsAppApiSender.normalizeApiVersion('   '), 'v21.0');
    });

    test('bentuk yang tidak masuk akal ditolak', () {
      expect(WhatsAppApiSender.normalizeApiVersion('21'), isNull);
      expect(WhatsAppApiSender.normalizeApiVersion('v21'), isNull);
      expect(WhatsAppApiSender.normalizeApiVersion('versi 21'), isNull);
      expect(WhatsAppApiSender.normalizeApiVersion('v21.0.1'), isNull);
    });
  });

  group('permintaan ke Meta', () {
    late AppDatabase db;
    late SettingsRepository settings;

    const message = 'Halo Budi\n\n1. Cuci Kiloan\n   3,5 kg × Rp 7.000\n'
        '*Total: Rp 24.500*';

    setUp(() async {
      db = AppDatabase.instance;
      await db.close();
      await db.openInMemory();

      settings = SettingsRepository(db);
      await settings.loadAll(force: true);
      await settings.setAll({
        SettingsKeys.whatsappPhoneNumberId: '123456',
        SettingsKeys.whatsappToken: 'token-uji',
      });
    });

    tearDown(() async => db.close());

    test('dengan template, isi pesan dikirim tanpa baris baru', () async {
      await settings.set(SettingsKeys.whatsappTemplateName, 'nota_laundry');

      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final result = await WhatsAppApiSender(settings, client: client)
          .send(phone: '6281234567890', message: message);

      expect(result.sent, isTrue);
      expect(body!['type'], 'template');

      final param =
          (body!['template'] as Map)['components'][0]['parameters'][0]['text']
              as String;
      expect(param.contains('\n'), isFalse);
      expect(param, contains('1. Cuci Kiloan | 3,5 kg'));
    });

    test('tanpa template, teks biasa tetap berbaris-baris', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      await WhatsAppApiSender(settings, client: client)
          .send(phone: '6281234567890', message: message);

      expect(body!['type'], 'text');
      expect((body!['text'] as Map)['body'], message);
    });

    test('penolakan Meta ditampilkan dengan alasannya', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'error': {'message': 'Invalid parameter', 'code': 100},
            }),
            400,
          ));

      final result = await WhatsAppApiSender(settings, client: client)
          .send(phone: '6281234567890', message: message);

      expect(result.sent, isFalse);
      expect(result.message, contains('Invalid parameter'));
      expect(result.message, contains('400'));
    });
  });
}
