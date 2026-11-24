import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/services/backup/backup_service.dart';

void main() {
  const appDir = '/storage/emulated/0/Android/data/com.manise.laundry/files';
  const appFolder = '$appDir/backup';
  const root = '/storage/emulated/0';

  group('sharedStorageRoot', () {
    test('memotong folder aplikasi menjadi akar penyimpanan', () {
      expect(sharedStorageRoot(appDir), root);
    });

    test('jalur tanpa /Android/ tidak punya akar bersama', () {
      expect(sharedStorageRoot('/data/user/0/com.manise.laundry/files'),
          isNull);
    });
  });

  group('folderKindOf', () {
    test('kosong dan app berarti folder aplikasi', () {
      expect(folderKindOf(''), BackupFolderKind.app);
      expect(folderKindOf('app'), BackupFolderKind.app);
      expect(folderKindOf('  '), BackupFolderKind.app);
    });

    test('kata kunci dikenali', () {
      expect(folderKindOf('download'), BackupFolderKind.download);
      expect(folderKindOf('documents'), BackupFolderKind.documents);
    });

    test('jalur lengkap adalah folder pilihan sendiri', () {
      expect(folderKindOf('$root/Download/Usaha'), BackupFolderKind.custom);
    });
  });

  group('folderPathFor', () {
    test('Download dan Documents memakai subfolder aplikasi', () {
      expect(
        folderPathFor('download', appFolder: appFolder, storageRoot: root),
        '$root/Download/LaundryManise',
      );
      expect(
        folderPathFor('documents', appFolder: appFolder, storageRoot: root),
        '$root/Documents/LaundryManise',
      );
    });

    test('folder aplikasi dan folder pilihan sendiri apa adanya', () {
      expect(folderPathFor('', appFolder: appFolder, storageRoot: root),
          appFolder);
      expect(
        folderPathFor(' $root/Download/Usaha ',
            appFolder: appFolder, storageRoot: root),
        '$root/Download/Usaha',
      );
    });

    test('tanpa penyimpanan bersama, Download tidak bisa dipilih', () {
      expect(
        folderPathFor('download', appFolder: appFolder, storageRoot: null),
        isNull,
      );
      expect(folderPathFor('', appFolder: appFolder, storageRoot: null),
          appFolder);
    });
  });

  test('hanya folder aplikasi yang ikut terhapus saat aplikasi dicopot', () {
    const app = BackupFolder(kind: BackupFolderKind.app, path: appFolder);
    const download =
        BackupFolder(kind: BackupFolderKind.download, path: '$root/Download');

    expect(app.survivesUninstall, isFalse);
    expect(download.survivesUninstall, isTrue);
  });
}
