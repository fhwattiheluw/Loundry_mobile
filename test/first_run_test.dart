import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/core/security.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/repositories/master_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late UserRepository users;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();
    users = UserRepository(db);
  });

  tearDown(() async => db.close());

  group('pemasangan baru', () {
    test('pemilik sudah ada tetapi belum punya PIN', () async {
      final owners =
          (await users.all()).where((u) => u.role == UserRole.owner).toList();

      expect(owners.length, 1);
      expect(owners.single.pinHash, isEmpty);
      expect(await users.ownerPinNotSet(), isTrue);
    });

    test('tidak ada PIN bawaan yang bisa dipakai masuk', () async {
      // Dulu semua pemasangan memakai 1234. Sekarang tidak ada PIN yang
      // cocok sama sekali sebelum pemilik membuatnya sendiri.
      for (final guess in ['1234', '0000', '123456', '']) {
        expect(await users.authenticate(guess), isNull, reason: guess);
      }
    });
  });

  group('membuat PIN pertama', () {
    test('pemilik bisa masuk dengan PIN yang baru dibuat', () async {
      final owner = await users.createFirstOwnerPin('2580');

      expect(owner.role, UserRole.owner);
      expect(verifyPin('2580', owner.pinHash), isTrue);
      expect(await users.ownerPinNotSet(), isFalse);

      final login = await users.authenticate('2580');
      expect(login?.id, owner.id);
    });

    test('PIN lama (1234) tetap tidak berlaku sesudahnya', () async {
      await users.createFirstOwnerPin('2580');
      expect(await users.authenticate('1234'), isNull);
    });

    test('tidak bisa dibuat dua kali, supaya PIN pemilik tidak bisa direbut',
        () async {
      await users.createFirstOwnerPin('2580');

      // Tanpa pengaman ini, siapa pun yang memegang HP bisa mengganti PIN
      // pemilik tanpa mengetahui PIN lamanya.
      expect(() => users.createFirstOwnerPin('9999'), throwsStateError);

      expect(await users.authenticate('9999'), isNull);
      expect(await users.authenticate('2580'), isNotNull);
    });
  });

  group('pemasangan lama', () {
    test('pemilik yang sudah punya PIN tidak dianggap pemasangan baru',
        () async {
      // Data lama dibuat dengan PIN bawaan 1234. Ia harus tetap masuk lewat
      // layar PIN seperti biasa, bukan dipaksa lewat wizard pemasangan baru.
      final owner = (await users.all()).first;
      await users.setPin(owner.id!, '1234');

      expect(await users.ownerPinNotSet(), isFalse);
      expect((await users.authenticate('1234'))?.id, owner.id);
    });

    test('createFirstOwnerPin menolak pemilik yang sudah punya PIN', () async {
      final owner = (await users.all()).first;
      await users.setPin(owner.id!, '1234');

      expect(() => users.createFirstOwnerPin('9999'), throwsStateError);
      expect(await users.authenticate('9999'), isNull);
    });
  });
}
