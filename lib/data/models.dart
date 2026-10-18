DateTime? _d(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
double? _dbl(Object? v) => v == null ? null : (v as num).toDouble();

class Profile {
  final int? id;
  final String name;
  final DateTime? birthDate;
  final String? sex; // 'K' / 'M'
  final double? heightCm;
  final String? bloodType;
  final String? allergies;
  final String? chronic;
  final String? medications;
  final String? notes;
  final int color;

  const Profile({
    this.id,
    required this.name,
    this.birthDate,
    this.sex,
    this.heightCm,
    this.bloodType,
    this.allergies,
    this.chronic,
    this.medications,
    this.notes,
    this.color = 0xFF0E7466,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'birth_date': _ms(birthDate),
        'sex': sex,
        'height_cm': heightCm,
        'blood_type': bloodType,
        'allergies': allergies,
        'chronic': chronic,
        'medications': medications,
        'notes': notes,
        'color': color,
      };

  static Profile fromMap(Map<String, Object?> m) => Profile(
        id: m['id'] as int,
        name: m['name'] as String,
        birthDate: _d(m['birth_date']),
        sex: m['sex'] as String?,
        heightCm: _dbl(m['height_cm']),
        bloodType: m['blood_type'] as String?,
        allergies: m['allergies'] as String?,
        chronic: m['chronic'] as String?,
        medications: m['medications'] as String?,
        notes: m['notes'] as String?,
        color: (m['color'] as int?) ?? 0xFF0E7466,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

/// Typy pomiarów ciała i parametrów życiowych.
class MType {
  final String key;
  final String name;
  final String unit;
  final bool twoValues;
  final double? low, high;
  const MType(this.key, this.name, this.unit, {this.twoValues = false, this.low, this.high});

  static const weight = MType('WEIGHT', 'Masa ciała', 'kg');
  static const bp = MType('BP', 'Ciśnienie krwi', 'mmHg', twoValues: true, low: 90, high: 135);
  static const pulse = MType('PULSE', 'Tętno', 'ud/min', low: 50, high: 100);
  static const glucose = MType('GLUCOSE', 'Glukoza (glukometr)', 'mg/dl', low: 70, high: 140);
  static const temp = MType('TEMP', 'Temperatura', '°C', low: 36.0, high: 37.2);
  static const spo2 = MType('SPO2', 'Saturacja SpO₂', '%', low: 95, high: 100);
  static const waist = MType('WAIST', 'Obwód talii', 'cm');
  static const height = MType('HEIGHT', 'Wzrost', 'cm');

  static const all = [weight, bp, pulse, glucose, temp, spo2, waist, height];
  static MType byKey(String k) => all.firstWhere((t) => t.key == k, orElse: () => weight);
}

class Measurement {
  final int? id;
  final int profileId;
  final DateTime date;
  final String type;
  final double value;
  final double? value2;
  final String? note;

  const Measurement({this.id, required this.profileId, required this.date, required this.type, required this.value, this.value2, this.note});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'profile_id': profileId,
        'date': _ms(date),
        'type': type,
        'value': value,
        'value2': value2,
        'note': note,
      };

  static Measurement fromMap(Map<String, Object?> m) => Measurement(
        id: m['id'] as int,
        profileId: m['profile_id'] as int,
        date: _d(m['date'])!,
        type: m['type'] as String,
        value: _dbl(m['value'])!,
        value2: _dbl(m['value2']),
        note: m['note'] as String?,
      );
}

class MedDocument {
  final int? id;
  final int profileId;
  final DateTime date;
  final String title;
  final String category;
  final String? facility;
  final String? doctor;
  final String? notes;
  final String? extractedText;
  final DateTime created;
  final bool favorite;
  final String? report; // JSON opisu lekarza (DoctorReport)
  final DateTime? followUp; // zalecony termin kontroli

  const MedDocument({
    this.id,
    required this.profileId,
    required this.date,
    required this.title,
    required this.category,
    this.facility,
    this.doctor,
    this.notes,
    this.extractedText,
    required this.created,
    this.favorite = false,
    this.report,
    this.followUp,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'profile_id': profileId,
        'date': _ms(date),
        'title': title,
        'category': category,
        'facility': facility,
        'doctor': doctor,
        'notes': notes,
        'extracted_text': extractedText,
        'created': _ms(created),
        'favorite': favorite ? 1 : 0,
        'report': report,
        'follow_up': _ms(followUp),
      };

  static MedDocument fromMap(Map<String, Object?> m) => MedDocument(
        id: m['id'] as int,
        profileId: m['profile_id'] as int,
        date: _d(m['date'])!,
        title: m['title'] as String,
        category: m['category'] as String,
        facility: m['facility'] as String?,
        doctor: m['doctor'] as String?,
        notes: m['notes'] as String?,
        extractedText: m['extracted_text'] as String?,
        created: _d(m['created'])!,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        report: m['report'] as String?,
        followUp: _d(m['follow_up']),
      );

  MedDocument copyWith({DateTime? date, String? title, String? category, String? facility, String? doctor, String? notes, String? extractedText, bool? favorite, String? report, DateTime? followUp, bool clearFollowUp = false}) =>
      MedDocument(
        id: id,
        profileId: profileId,
        date: date ?? this.date,
        title: title ?? this.title,
        category: category ?? this.category,
        facility: facility ?? this.facility,
        doctor: doctor ?? this.doctor,
        notes: notes ?? this.notes,
        extractedText: extractedText ?? this.extractedText,
        created: created,
        favorite: favorite ?? this.favorite,
        report: report ?? this.report,
        followUp: clearFollowUp ? null : (followUp ?? this.followUp),
      );
}

class DocFile {
  final int? id;
  final int documentId;
  final String path; // względna ścieżka w katalogu aplikacji
  final String name;
  final String mime;
  final int size;
  final String kind; // 'source' – oryginał, 'figure' – grafika wykryta automatycznie, 'crop' – wycięta ręcznie

  const DocFile({this.id, required this.documentId, required this.path, required this.name, required this.mime, required this.size, this.kind = 'source'});

  bool get isGraphic => kind != 'source';

  bool get isPdf => mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
  bool get isImage => mime.startsWith('image/');

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'document_id': documentId,
        'path': path,
        'name': name,
        'mime': mime,
        'size': size,
        'kind': kind,
      };

  static DocFile fromMap(Map<String, Object?> m) => DocFile(
        id: m['id'] as int,
        documentId: m['document_id'] as int,
        path: m['path'] as String,
        name: m['name'] as String,
        mime: m['mime'] as String,
        size: m['size'] as int? ?? 0,
        kind: (m['kind'] as String?) ?? 'source',
      );
}

class LabResult {
  final int? id;
  final int profileId;
  final int? documentId;
  final DateTime date;
  final String key;
  final String name;
  final double? value;
  final String? valueText;
  final String unit;
  final double? refLow, refHigh;
  final String? flag;

  const LabResult({
    this.id,
    required this.profileId,
    this.documentId,
    required this.date,
    required this.key,
    required this.name,
    this.value,
    this.valueText,
    this.unit = '',
    this.refLow,
    this.refHigh,
    this.flag,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'profile_id': profileId,
        'document_id': documentId,
        'date': _ms(date),
        'key': key,
        'name': name,
        'value': value,
        'value_text': valueText,
        'unit': unit,
        'ref_low': refLow,
        'ref_high': refHigh,
        'flag': flag,
      };

  static LabResult fromMap(Map<String, Object?> m) => LabResult(
        id: m['id'] as int,
        profileId: m['profile_id'] as int,
        documentId: m['document_id'] as int?,
        date: _d(m['date'])!,
        key: m['key'] as String,
        name: m['name'] as String,
        value: _dbl(m['value']),
        valueText: m['value_text'] as String?,
        unit: (m['unit'] as String?) ?? '',
        refLow: _dbl(m['ref_low']),
        refHigh: _dbl(m['ref_high']),
        flag: m['flag'] as String?,
      );
}
