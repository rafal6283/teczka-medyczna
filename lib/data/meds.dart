import 'db.dart';

class Med {
  final int? id;
  final int profileId;
  final String name;
  final String dose; // np. „1 tabl.”, „5 mg”
  final List<String> times; // „08:00”, „20:00”
  final bool active, remind;
  final String notes;
  const Med({this.id, required this.profileId, required this.name, this.dose = '', required this.times, this.active = true, this.remind = true, this.notes = ''});

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'name': name,
        'dose': dose,
        'times': times.join(','),
        'active': active ? 1 : 0,
        'remind': remind ? 1 : 0,
        'notes': notes,
        'created': DateTime.now().millisecondsSinceEpoch,
      };

  factory Med.fromMap(Map<String, Object?> m) => Med(
        id: m['id'] as int?,
        profileId: m['profile_id'] as int,
        name: m['name'] as String,
        dose: m['dose'] as String? ?? '',
        times: ((m['times'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList()..sort(),
        active: (m['active'] as int? ?? 1) == 1,
        remind: (m['remind'] as int? ?? 1) == 1,
        notes: m['notes'] as String? ?? '',
      );
}

/// Dawka zaplanowana na dzień: lek, godzina i stan (null = nie odhaczona).
class Dose {
  final Med med;
  final String day, time;
  final bool? taken;
  const Dose(this.med, this.day, this.time, this.taken);
  DateTime get at => DateTime.parse('${day}T$time:00');
}

String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Przestrzeganie: dawki zaplanowane, przyjęte i pominięte (minione, nieodhaczone albo odhaczone jako pominięte).
class Adherence {
  final int planned, taken, missed;
  const Adherence(this.planned, this.taken, this.missed);
  double get pct => planned == 0 ? 1 : taken / planned;
}

extension MedsDb on AppDb {
  Future<List<Med>> meds(int profileId, {bool onlyActive = false}) async => [
        for (final r in await db.query('meds',
            where: onlyActive ? 'profile_id=? AND active=1' : 'profile_id=?', whereArgs: [profileId], orderBy: 'active DESC, name COLLATE NOCASE'))
          Med.fromMap(r)
      ];

  Future<List<Med>> allActiveMeds() async => [for (final r in await db.query('meds', where: 'active=1')) Med.fromMap(r)];

  Future<int> saveMed(Med m) async {
    final data = m.toMap()..remove('id');
    if (m.id == null) {
      final id = await db.insert('meds', data);
      changed();
      return id;
    }
    data.remove('created');
    await db.update('meds', data, where: 'id=?', whereArgs: [m.id]);
    changed();
    return m.id!;
  }

  Future<void> deleteMed(int id) async {
    await db.delete('meds', where: 'id=?', whereArgs: [id]);
    changed();
  }

  /// Odhaczenie dawki: true przyjęta, false pominięta, null – cofnięcie.
  Future<void> markDose(Med m, String day, String time, bool? taken) async {
    if (taken == null) {
      await db.delete('med_log', where: 'med_id=? AND day=? AND time=?', whereArgs: [m.id, day, time]);
    } else {
      await db.rawInsert('INSERT OR REPLACE INTO med_log(med_id, day, time, taken, at) VALUES(?,?,?,?,?)',
          [m.id, day, time, taken ? 1 : 0, DateTime.now().millisecondsSinceEpoch]);
    }
    changed();
  }

  /// Dzień → godzina → przyjęta?
  Future<Map<int, Map<String, Map<String, bool>>>> doseLog(int profileId, String fromDay) async {
    final out = <int, Map<String, Map<String, bool>>>{};
    for (final r in await db.rawQuery(
        'SELECT l.med_id, l.day, l.time, l.taken FROM med_log l JOIN meds m ON m.id = l.med_id WHERE m.profile_id=? AND l.day>=?',
        [profileId, fromDay])) {
      ((out[r['med_id'] as int] ??= {})[r['day'] as String] ??= {})[r['time'] as String] = r['taken'] == 1;
    }
    return out;
  }

  Future<List<Dose>> dosesOn(int profileId, DateTime day) async {
    final d = isoDay(day);
    final log = await doseLog(profileId, d);
    return [
      for (final m in await meds(profileId, onlyActive: true))
        for (final t in m.times) Dose(m, d, t, log[m.id]?[d]?[t])
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Przestrzeganie dzień po dniu z ostatnich [days] dni (dzisiaj tylko minione dawki).
  Future<Map<String, Adherence>> adherence(int profileId, {int days = 30}) async {
    final now = DateTime.now();
    final from = isoDay(now.subtract(Duration(days: days - 1)));
    final log = await doseLog(profileId, from);
    final ms = await meds(profileId, onlyActive: true);
    final out = <String, Adherence>{};
    for (var i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final iso = isoDay(d);
      var planned = 0, taken = 0, missed = 0;
      for (final m in ms) {
        for (final t in m.times) {
          final at = DateTime.parse('${iso}T$t:00');
          if (at.isAfter(now)) continue;
          final v = log[m.id]?[iso]?[t];
          planned++;
          if (v == true) {
            taken++;
          } else if (v == false || now.difference(at).inHours >= 3) {
            missed++; // nieodhaczona po 3 godzinach liczy się jako pominięta
          }
        }
      }
      if (planned > 0) out[iso] = Adherence(planned, taken, missed);
    }
    return out;
  }
}
