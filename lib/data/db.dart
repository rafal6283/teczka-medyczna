import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Centralny dostęp do danych + powiadamianie ekranów o zmianach.
class AppDb extends ChangeNotifier {
  AppDb._();
  static final AppDb I = AppDb._();

  Database? _db;
  late Directory root; // katalog dokumentów aplikacji
  int? currentProfileId;
  int revision = 0;

  Database get db => _db!;
  Directory get filesDir => Directory(p.join(root.path, 'pliki'));
  String get dbPath => p.join(root.path, 'teczka.db');

  String initStage = '';

  Future<void> init() async {
    initStage = 'katalog dokumentów';
    root = await getApplicationDocumentsDirectory();
    initStage = 'folder plików';
    await filesDir.create(recursive: true);
    initStage = 'baza danych';
    await _open();
    initStage = 'ustawienia';
    final prefs = await SharedPreferences.getInstance();
    initStage = 'profile';
    currentProfileId = prefs.getInt('profile');
    final profiles = await getProfiles();
    if (profiles.isEmpty) {
      currentProfileId = null;
    } else if (currentProfileId == null || !profiles.any((x) => x.id == currentProfileId)) {
      currentProfileId = profiles.first.id;
    }
    initStage = 'gotowe';
  }

  Future<void> _open() async {
    _db = await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (d, from, to) async {
        if (from < 2) {
          await d.execute('ALTER TABLE documents ADD COLUMN report TEXT');
          await d.execute('ALTER TABLE documents ADD COLUMN follow_up INTEGER');
        }
      },
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE profiles(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, birth_date INTEGER, sex TEXT, height_cm REAL,
          blood_type TEXT, allergies TEXT, chronic TEXT, medications TEXT, notes TEXT, color INTEGER)''');
        await d.execute('''CREATE TABLE measurements(
          id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
          date INTEGER NOT NULL, type TEXT NOT NULL, value REAL NOT NULL, value2 REAL, note TEXT)''');
        await d.execute('''CREATE TABLE documents(
          id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
          date INTEGER NOT NULL, title TEXT NOT NULL, category TEXT NOT NULL, facility TEXT, doctor TEXT, notes TEXT,
          extracted_text TEXT, created INTEGER NOT NULL, favorite INTEGER DEFAULT 0, report TEXT, follow_up INTEGER)''');
        await d.execute('''CREATE TABLE doc_files(
          id INTEGER PRIMARY KEY AUTOINCREMENT, document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          path TEXT NOT NULL, name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER, kind TEXT DEFAULT 'source')''');
        await d.execute('''CREATE TABLE results(
          id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
          document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE, date INTEGER NOT NULL, key TEXT NOT NULL,
          name TEXT NOT NULL, value REAL, value_text TEXT, unit TEXT, ref_low REAL, ref_high REAL, flag TEXT)''');
        await d.execute('CREATE INDEX idx_results_pk ON results(profile_id, key, date)');
        await d.execute('CREATE INDEX idx_docs_p ON documents(profile_id, date)');
        await d.execute('CREATE INDEX idx_meas_p ON measurements(profile_id, type, date)');
      },
    );
  }

  /// Zamknięcie i ponowne otwarcie (po przywróceniu kopii zapasowej).
  Future<void> reopen() async {
    await _db?.close();
    _db = null;
    await init();
    changed();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  Future<void> selectProfile(int? id) async {
    currentProfileId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('profile');
    } else {
      await prefs.setInt('profile', id);
    }
    changed();
  }

  // ---------- profile ----------
  Future<List<Profile>> getProfiles() async => (await db.query('profiles', orderBy: 'name COLLATE NOCASE')).map(Profile.fromMap).toList();

  Future<Profile?> getProfile(int id) async {
    final r = await db.query('profiles', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : Profile.fromMap(r.first);
  }

  Future<Profile?> current() async => currentProfileId == null ? null : getProfile(currentProfileId!);

  Future<int> saveProfile(Profile x) async {
    int id;
    if (x.id == null) {
      id = await db.insert('profiles', x.toMap());
    } else {
      await db.update('profiles', x.toMap(), where: 'id=?', whereArgs: [x.id]);
      id = x.id!;
    }
    if (currentProfileId == null) await selectProfile(id);
    changed();
    return id;
  }

  Future<void> deleteProfile(int id) async {
    final docs = await getDocuments(id);
    for (final d in docs) {
      await _deleteFilesOf(d.id!);
    }
    await db.delete('profiles', where: 'id=?', whereArgs: [id]);
    final rest = await getProfiles();
    await selectProfile(rest.isEmpty ? null : rest.first.id);
  }

  // ---------- pomiary ----------
  Future<List<Measurement>> getMeasurements(int profileId, {String? type}) async {
    final r = await db.query('measurements',
        where: type == null ? 'profile_id=?' : 'profile_id=? AND type=?', whereArgs: type == null ? [profileId] : [profileId, type], orderBy: 'date');
    return r.map(Measurement.fromMap).toList();
  }

  Future<void> saveMeasurement(Measurement m) async {
    if (m.id == null) {
      await db.insert('measurements', m.toMap());
    } else {
      await db.update('measurements', m.toMap(), where: 'id=?', whereArgs: [m.id]);
    }
    changed();
  }

  Future<void> deleteMeasurement(int id) async {
    await db.delete('measurements', where: 'id=?', whereArgs: [id]);
    changed();
  }

  // ---------- dokumenty ----------
  Future<List<MedDocument>> getDocuments(int profileId) async =>
      (await db.query('documents', where: 'profile_id=?', whereArgs: [profileId], orderBy: 'date DESC, id DESC')).map(MedDocument.fromMap).toList();

  Future<MedDocument?> getDocument(int id) async {
    final r = await db.query('documents', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : MedDocument.fromMap(r.first);
  }

  Future<int> saveDocument(MedDocument d) async {
    int id;
    if (d.id == null) {
      id = await db.insert('documents', d.toMap());
    } else {
      await db.update('documents', d.toMap(), where: 'id=?', whereArgs: [d.id]);
      // data dokumentu = data wyników z tego dokumentu
      await db.update('results', {'date': d.date.millisecondsSinceEpoch}, where: 'document_id=?', whereArgs: [d.id]);
      id = d.id!;
    }
    changed();
    return id;
  }

  Future<void> deleteDocument(int id) async {
    await _deleteFilesOf(id);
    await db.delete('documents', where: 'id=?', whereArgs: [id]);
    changed();
  }

  Future<void> _deleteFilesOf(int documentId) async {
    for (final f in await getFiles(documentId)) {
      final file = File(absPath(f.path));
      if (await file.exists()) await file.delete();
    }
  }

  Future<List<DocFile>> getFiles(int documentId) async =>
      (await db.query('doc_files', where: 'document_id=?', whereArgs: [documentId], orderBy: 'id')).map(DocFile.fromMap).toList();

  Future<Map<int, int>> fileCounts(int profileId) async {
    final r = await db.rawQuery(
        'SELECT f.document_id AS d, COUNT(*) AS c FROM doc_files f JOIN documents d ON d.id=f.document_id WHERE d.profile_id=? GROUP BY f.document_id', [profileId]);
    return {for (final x in r) x['d'] as int: x['c'] as int};
  }

  Future<Map<int, int>> resultCounts(int profileId) async {
    final r = await db.rawQuery('SELECT document_id AS d, COUNT(*) AS c FROM results WHERE profile_id=? AND document_id IS NOT NULL GROUP BY document_id', [profileId]);
    return {for (final x in r) x['d'] as int: x['c'] as int};
  }

  Future<void> addFile(DocFile f) async {
    await db.insert('doc_files', f.toMap());
    changed();
  }

  Future<void> deleteFile(DocFile f) async {
    final file = File(absPath(f.path));
    if (await file.exists()) await file.delete();
    await db.delete('doc_files', where: 'id=?', whereArgs: [f.id]);
    changed();
  }

  String absPath(String rel) => p.join(root.path, rel);

  // ---------- wyniki ----------
  Future<List<LabResult>> getResults(int profileId, {String? key, int? documentId}) async {
    final where = <String>['profile_id=?'];
    final args = <Object>[profileId];
    if (key != null) {
      where.add('key=?');
      args.add(key);
    }
    if (documentId != null) {
      where.add('document_id=?');
      args.add(documentId);
    }
    final r = await db.query('results', where: where.join(' AND '), whereArgs: args, orderBy: 'date, id');
    return r.map(LabResult.fromMap).toList();
  }

  Future<void> saveResult(LabResult r) async {
    if (r.id == null) {
      await db.insert('results', r.toMap());
    } else {
      await db.update('results', r.toMap(), where: 'id=?', whereArgs: [r.id]);
    }
    changed();
  }

  Future<void> replaceResults(int documentId, List<LabResult> list) async {
    await db.transaction((t) async {
      await t.delete('results', where: 'document_id=?', whereArgs: [documentId]);
      for (final r in list) {
        await t.insert('results', r.toMap());
      }
    });
    changed();
  }

  Future<void> deleteResult(int id) async {
    await db.delete('results', where: 'id=?', whereArgs: [id]);
    changed();
  }

  /// Zmienia nazwę/klucz parametru we wszystkich wynikach profilu (scalanie nieznanych parametrów).
  Future<void> renameParam(int profileId, String oldKey, String newKey, String newName) async {
    await db.update('results', {'key': newKey, 'name': newName}, where: 'profile_id=? AND key=?', whereArgs: [profileId, oldKey]);
    changed();
  }

  Future<List<MedDocument>> searchDocuments(int profileId, String q) async {
    final like = '%${q.replaceAll('%', '')}%';
    final r = await db.query('documents',
        where: 'profile_id=? AND (title LIKE ? OR facility LIKE ? OR doctor LIKE ? OR notes LIKE ? OR extracted_text LIKE ? OR category LIKE ? OR report LIKE ?)',
        whereArgs: [profileId, like, like, like, like, like, like, like],
        orderBy: 'date DESC');
    return r.map(MedDocument.fromMap).toList();
  }
}
