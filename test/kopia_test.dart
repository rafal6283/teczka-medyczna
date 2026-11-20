import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofr_backup_ui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teczka_zdrowia/data/db.dart';
import 'package:teczka_zdrowia/data/koofr_backup.dart';
import 'package:teczka_zdrowia/data/models.dart';

/// Kopia na Koofr → nowy telefon (tylko kod odzyskiwania) → przywrócenie: profile i pliki dokumentów wracają.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('teczka');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => dir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HttpOverrides.global = null; // serwer WebDAV w pamięci potrzebuje prawdziwego HttpClient
  });

  test('przywrócenie kopii na czystym telefonie', () async {
    final db = AppDb.I;
    await db.init();
    await db.saveProfile(const Profile(name: 'Rafał'));
    await File(p.join(db.filesDir.path, 'wynik.pdf')).writeAsString('%PDF-1.4 morfologia');
    final restored = await kopiaAdapteraNaNowyTelefon(TeczkaBackup());
    expect(restored.blobs.keys, ['pliki/wynik.pdf']);

    // „nowy telefon”: pusta baza i brak plików
    await db.close();
    await File(db.dbPath).delete();
    await db.filesDir.delete(recursive: true);
    await db.init();
    expect(await db.getProfiles(), isEmpty);

    await TeczkaBackup().import(restored, (_) {});
    expect((await db.getProfiles()).map((x) => x.name), ['Rafał']);
    expect(await File(p.join(db.filesDir.path, 'wynik.pdf')).readAsString(), contains('morfologia'));
  });
}
