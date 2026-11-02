import 'dart:convert';
import 'dart:io';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'meds.dart';

/// Kopia Teczki na rodzinnym Koofr: baza jako dane, każdy dokument (PDF, zdjęcie) jako osobny
/// załącznik — wysyłany tylko raz, więc codzienna kopia nie mnoży miejsca.
class TeczkaBackup extends BackupAdapter {
  @override
  String get appId => 'teczka';
  @override
  String get appName => 'Teczka Zdrowia';
  @override
  String get contentNote => 'W kopii są wszystkie profile, wyniki, pomiary i pliki dokumentów.';

  @override
  ExchangeAdapter get exchange => _TeczkaExchange();

  @override
  Future<BackupContent> export() async {
    final db = AppDb.I;
    await db.close();
    List<int> dbBytes;
    try {
      dbBytes = await File(db.dbPath).readAsBytes();
    } finally {
      await db.reopen();
    }
    final blobs = <BackupBlob>[];
    if (await db.filesDir.exists()) {
      await for (final e in db.filesDir.list()) {
        if (e is File) blobs.add(BackupBlob('pliki/${p.basename(e.path)}', e.readAsBytes));
      }
    }
    return BackupContent(dbBytes, blobs);
  }

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    final db = AppDb.I;
    if (r.data.length < 16 || String.fromCharCodes(r.data.sublist(0, 15)) != 'SQLite format 3') {
      throw KoofrException('Kopia nie zawiera bazy Teczki.');
    }
    // Najpierw pobieramy wszystko obok, dopiero potem podmieniamy — przerwane pobieranie nie niszczy danych.
    final tmp = Directory(p.join(db.root.path, 'pliki.przywracanie'));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    var i = 0;
    for (final e in r.blobs.entries) {
      progress('Dokumenty: ${++i} z ${r.blobs.length}');
      if (!e.key.startsWith('pliki/') || e.key.contains('..')) continue;
      await File(p.join(tmp.path, p.basename(e.key))).writeAsBytes(await r.blob(e.value), flush: true);
    }
    progress('Zapisywanie…');
    await db.close();
    final cur = File(db.dbPath);
    if (await cur.exists()) await cur.copy('${db.dbPath}.przed-przywroceniem');
    await cur.writeAsBytes(r.data, flush: true);
    if (await db.filesDir.exists()) await db.filesDir.delete(recursive: true);
    await tmp.rename(db.filesDir.path);
    await db.reopen();
  }
}


/// Przyjmowanie leków (czynniki-dnia) dla Polar EKG: czy pominięte dawki poprzedzają napady AF.
/// Udostępniany jest profil z lekami (pierwszy taki) – zwykle właściciel telefonu.
class _TeczkaExchange extends ExchangeAdapter {
  @override
  String get publishes => 'Przyjmowanie leków dzień po dniu (bez nazw leków) – dla Polar EKG';

  @override
  Future<Map<String, List<int>?>> export() async {
    final db = AppDb.I;
    int? pid;
    for (final p in await db.getProfiles()) {
      if ((await db.meds(p.id!)).isNotEmpty) {
        pid = p.id;
        break;
      }
    }
    if (pid == null) return {'czynniki-leki': null};
    final adh = await db.adherence(pid, days: 120);
    return {
      'czynniki-leki': utf8.encode(jsonEncode({
        'format': 'czynniki-dnia',
        'version': 1,
        'source': 'teczka',
        'exported_at': DateTime.now().millisecondsSinceEpoch,
        'days': [
          for (final e in adh.entries) {'date': e.key, 'doses': e.value.planned, 'taken': e.value.taken, 'missed': e.value.missed}
        ],
      })),
    };
  }
}
