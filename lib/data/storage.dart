import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'models.dart';

class Storage {
  static final _rnd = Random();

  static String mimeFor(String name) {
    final e = p.extension(name).toLowerCase();
    switch (e) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.heic':
        return 'image/heic';
      case '.webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  /// Kopiuje plik do katalogu aplikacji; zwraca ścieżkę względną.
  static Future<String> importFile(String sourcePath, String name) async {
    final ext = p.extension(name).toLowerCase();
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_rnd.nextInt(1 << 30)}';
    final rel = p.join('pliki', '$id$ext');
    final dest = File(AppDb.I.absPath(rel));
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    return rel;
  }

  static Future<String> importBytes(Uint8List bytes, String name) async {
    final ext = p.extension(name).toLowerCase();
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_rnd.nextInt(1 << 30)}';
    final rel = p.join('pliki', '$id$ext');
    final dest = File(AppDb.I.absPath(rel));
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes);
    return rel;
  }

  static Future<DocFile> attach(int documentId, String sourcePath, String name) async {
    final rel = await importFile(sourcePath, name);
    final size = await File(AppDb.I.absPath(rel)).length();
    final f = DocFile(documentId: documentId, path: rel, name: name, mime: mimeFor(name), size: size);
    await AppDb.I.addFile(f);
    return f;
  }

  static Future<DocFile> attachBytes(int documentId, Uint8List bytes, String name, {String kind = 'source'}) async {
    final rel = await importBytes(bytes, name);
    final f = DocFile(documentId: documentId, path: rel, name: name, mime: mimeFor(name), size: bytes.length, kind: kind);
    await AppDb.I.addFile(f);
    return f;
  }

  // ---------- kopia zapasowa ----------

  static Future<Uint8List> buildBackup() async {
    final db = AppDb.I;
    await db.close();
    try {
      final archive = Archive();
      final dbBytes = await File(db.dbPath).readAsBytes();
      archive.addFile(ArchiveFile('teczka.db', dbBytes.length, dbBytes));
      if (await db.filesDir.exists()) {
        await for (final e in db.filesDir.list()) {
          if (e is File) {
            final b = await e.readAsBytes();
            archive.addFile(ArchiveFile('pliki/${p.basename(e.path)}', b.length, b));
          }
        }
      }
      final zipped = ZipEncoder().encode(archive);
      return Uint8List.fromList(zipped!);
    } finally {
      await db.reopen();
    }
  }

  /// Zapisuje kopię; zwraca true jeśli użytkownik wybrał miejsce.
  static Future<bool> exportBackup() async {
    final bytes = await buildBackup();
    final now = DateTime.now();
    final name = 'teczka-zdrowia-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.zip';
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Zapisz kopię zapasową', fileName: name, bytes: bytes);
    return path != null;
  }

  /// Przywraca kopię (zastępuje wszystkie dane). Zwraca komunikat błędu albo null.
  static Future<String?> importBackup() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return 'Anulowano';
    final f = res.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return 'Nie udało się odczytać pliku';
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return 'To nie jest plik kopii zapasowej (.zip)';
    }
    final dbEntry = archive.files.where((e) => e.name == 'teczka.db').toList();
    if (dbEntry.isEmpty) return 'W archiwum brakuje bazy danych teczka.db';

    final db = AppDb.I;
    await db.close();
    if (await db.filesDir.exists()) await db.filesDir.delete(recursive: true);
    await db.filesDir.create(recursive: true);
    for (final e in archive.files) {
      if (!e.isFile) continue;
      if (e.name == 'teczka.db') {
        await File(db.dbPath).writeAsBytes(e.content as List<int>, flush: true);
      } else if (e.name.startsWith('pliki/') && !e.name.contains('..')) {
        await File(p.join(db.filesDir.path, p.basename(e.name))).writeAsBytes(e.content as List<int>, flush: true);
      }
    }
    await db.reopen();
    return null;
  }
}
