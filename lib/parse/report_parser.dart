// Analiza opisowych wyników (endoskopia, Holter, obrazowe, wypisy): rodzaj badania,
// sekcje opisu lekarza, istotne zdania (z obsługą zaprzeczeń) i zalecane terminy kontroli.

import 'dart:convert';

import 'text_utils.dart';

class ExamType {
  final String key;
  final String name;
  final List<String> words; // znormalizowane frazy
  const ExamType(this.key, this.name, this.words);
}

class ReportFinding {
  final String sentence;
  final bool abnormal;
  final List<String> keywords;
  ReportFinding(this.sentence, this.abnormal, this.keywords);

  Map<String, Object?> toJson() => {'s': sentence, 'a': abnormal, 'k': keywords};
  static ReportFinding fromJson(Map<String, dynamic> m) =>
      ReportFinding(m['s'] as String, m['a'] as bool? ?? false, (m['k'] as List? ?? []).cast<String>());
}

class DoctorReport {
  String? examType; // klucz ExamType
  String description;
  String conclusions;
  String recommendations;
  List<ReportFinding> findings;
  DateTime? followUp;
  String? followUpText;

  DoctorReport({
    this.examType,
    this.description = '',
    this.conclusions = '',
    this.recommendations = '',
    List<ReportFinding>? findings,
    this.followUp,
    this.followUpText,
  }) : findings = findings ?? [];

  bool get isEmpty => description.trim().isEmpty && conclusions.trim().isEmpty && recommendations.trim().isEmpty;
  List<ReportFinding> get abnormal => findings.where((f) => f.abnormal).toList();
  String? get examName => examType == null ? null : ReportParser.typeByKey(examType!)?.name;

  String toJson() => jsonEncode({
        't': examType,
        'd': description,
        'c': conclusions,
        'r': recommendations,
        'f': findings.map((e) => e.toJson()).toList(),
        'u': followUp?.millisecondsSinceEpoch,
        'ut': followUpText,
      });

  static DoctorReport? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return DoctorReport(
        examType: m['t'] as String?,
        description: m['d'] as String? ?? '',
        conclusions: m['c'] as String? ?? '',
        recommendations: m['r'] as String? ?? '',
        findings: (m['f'] as List? ?? []).map((e) => ReportFinding.fromJson(e as Map<String, dynamic>)).toList(),
        followUp: m['u'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['u'] as int),
        followUpText: m['ut'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Ponowna ocena zdań po ręcznej edycji tekstu.
  void reanalyze() {
    findings = ReportParser.findings('$description\n$conclusions');
  }
}

class ReportParser {
  static const types = [
    ExamType('EYE', 'Badanie okulistyczne', [
      'badanie okulistyczne', 'konsultacja okulistyczna', 'okulistyczn', 'refrakcj', 'autorefraktometr', 'ostrosc wzroku', 'visus', 'tonometri',
      'cisnienie wewnatrzgalkowe', 'pole widzenia', 'perymetri', 'keratometri', 'biometria oka', 'pachymetri', 'badanie dna oka', 'oct plamki',
      'oct tarczy', 'oct nerwu', 'recepta na okulary', 'dobor okularow'
    ]),
    ExamType('COLONO', 'Kolonoskopia', ['kolonoskopi', 'rektoskopi', 'sigmoidoskopi', 'endoskopia dolnego']),
    ExamType('GASTRO', 'Gastroskopia', ['gastroskopi', 'gastroduodenoskopi', 'ezofagogastroduodenoskopi', 'endoskopia gornego']),
    ExamType('HOLTER_EKG', 'Holter EKG', ['holter ekg', 'holtera ekg', 'badanie holterowskie', 'holter', 'ekg metoda holtera', '24 godzinne monitorowanie ekg']),
    ExamType('ABPM', 'Holter ciśnieniowy (ABPM)', ['abpm', 'holter rr', 'holter cisnieniowy', 'holter cisnienia', 'calodobowe monitorowanie cisnienia', '24 godzinne monitorowanie cisnienia']),
    ExamType('ECHO', 'Echo serca', ['echokardiografi', 'echo serca', 'echo serca', 'ultrasonografia serca']),
    ExamType('EKG', 'EKG', ['elektrokardiogra', 'ekg spoczynkowe', 'badanie ekg']),
    ExamType('ERGO', 'Próba wysiłkowa', ['proba wysilkowa', 'test wysilkowy', 'elektrokardiograficzna proba wysilkowa']),
    ExamType('HIST', 'Histopatologia', ['histopatologi', 'badanie histopatologiczne', 'wynik histopatologiczny']),
    ExamType('CYTO', 'Cytologia', ['cytologi']),
    ExamType('MAMMO', 'Mammografia', ['mammografi']),
    ExamType('USG', 'USG', ['usg', 'ultrasonografi', 'badanie usg', 'doppler']),
    ExamType('RTG', 'RTG', ['rtg', 'rentgen', 'zdjecie rtg', 'radiogram']),
    ExamType('TK', 'Tomografia komputerowa', ['tomografia komputerowa', 'tomografii komputerowej', 'angio tk', 'badanie tk']),
    ExamType('MR', 'Rezonans magnetyczny', ['rezonans magnetyczny', 'rezonansu magnetycznego', 'badanie mr', 'mri']),
    ExamType('DXA', 'Densytometria', ['densytometri']),
    ExamType('SPIRO', 'Spirometria', ['spirometri']),
    ExamType('WYPIS', 'Wypis ze szpitala', ['karta informacyjna leczenia szpitalnego', 'wypis', 'epikryza']),
    ExamType('KONS', 'Konsultacja', ['konsultacj', 'porada lekarska', 'wizyta', 'karta wizyty']),
  ];

  static ExamType? typeByKey(String k) {
    for (final t in types) {
      if (t.key == k) return t;
    }
    return null;
  }

  static ExamType? detectType(String text) {
    final n = ' ${normText(text.length > 4000 ? text.substring(0, 4000) : text)} ';
    ExamType? best;
    var bestPos = 1 << 30;
    for (final t in types) {
      for (final w in t.words) {
        final i = n.indexOf(' $w');
        // wcześniej w tekście (nagłówek) = ważniejsze
        if (i >= 0 && i < bestPos) {
          bestPos = i;
          best = t;
        }
      }
    }
    return best;
  }

  // ---------- sekcje ----------

  static const _secDesc = ['opis badania', 'opis', 'przebieg badania', 'badanie przedmiotowe', 'wynik badania', 'wynik', 'przebieg hospitalizacji', 'ocena', 'analiza', 'komentarz'];
  static const _secConc = [
    'wnioski', 'wniosek', 'rozpoznanie', 'rozpoznania', 'podsumowanie', 'konkluzja', 'ocena koncowa', 'interpretacja', 'wynik histopatologiczny',
    'rozpoznanie histopatologiczne', 'diagnoza', 'opinia'
  ];
  static const _secRec = ['zalecenia', 'zalecenie', 'dalsze postepowanie', 'zalecono', 'zalecenia lekarskie', 'proponowane postepowanie', 'kontrola'];
  static const _secStop = ['lekarz', 'lekarz wykonujacy', 'lekarz opisujacy', 'podpis', 'pieczatka', 'data wydruku', 'strona', 'nr ksiegi', 'dane pacjenta'];

  static String? _heading(String line) {
    final n = normText(line);
    if (n.isEmpty || n.length > 60) return null;
    // nagłówek: "Wnioski:" / "WNIOSKI" / "Opis badania -"
    bool isHead(String w) {
      if (!(n == w || n.startsWith('$w '))) return false;
      final rest = n.substring(w.length).trim();
      return rest.isEmpty || line.contains(':') || line.trim() == line.trim().toUpperCase();
    }

    for (final w in _secConc) {
      if (isHead(w)) return 'c';
    }
    for (final w in _secRec) {
      if (isHead(w)) return 'r';
    }
    for (final w in _secStop) {
      if (isHead(w)) return 'x';
    }
    for (final w in _secDesc) {
      if (isHead(w)) return 'd';
    }
    return null;
  }

  static final _personal = RegExp(
      r'(pesel|pacjent|data urodzenia|adres|ul\.|nr ksiegi|regon|nip|tel\.|telefon|e-mail|strona \d|kod pocztowy|nr badania|nr zlecenia|zlecajacy|oddzial|data wydruku)',
      caseSensitive: false);

  static DoctorReport parse(String text, {DateTime? docDate}) {
    final type = detectType(text);
    final lines = text.split(RegExp(r'\r?\n'));
    final buf = {'d': StringBuffer(), 'c': StringBuffer(), 'r': StringBuffer()};
    String? cur;
    for (final raw in lines) {
      final line = raw.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
      if (line.isEmpty) continue;
      final h = _heading(line);
      if (h != null) {
        cur = h == 'x' ? null : h;
        // treść w tej samej linii po dwukropku
        final i = line.indexOf(':');
        if (cur != null && i >= 0 && i < line.length - 1) {
          final after = line.substring(i + 1).trim();
          if (after.isNotEmpty) buf[cur]!.writeln(after);
        }
        continue;
      }
      if (cur != null) {
        if (_personal.hasMatch(normText(line))) continue;
        buf[cur]!.writeln(line);
      }
    }
    var desc = _tidy(buf['d']!.toString());
    final conc = _tidy(buf['c']!.toString());
    final rec = _tidy(buf['r']!.toString());
    // brak nagłówków – bierzemy treść bez linii z danymi osobowymi
    if (desc.isEmpty && conc.isEmpty && rec.isEmpty && type != null) {
      final body = lines
          .map((l) => l.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim())
          .where((l) => l.length > 25 && !_personal.hasMatch(normText(l)) && RegExp(r'\p{L}{3,}', unicode: true).allMatches(l).length >= 4)
          .join('\n');
      desc = _tidy(body);
    }
    final all = '$desc\n$conc';
    final fu = followUp('$rec\n$conc\n$desc', docDate ?? DateTime.now());
    return DoctorReport(
      examType: type?.key,
      description: desc,
      conclusions: conc,
      recommendations: rec,
      findings: findings(all),
      followUp: fu?.$1,
      followUpText: fu?.$2,
    );
  }

  static String _tidy(String s) {
    final t = s.trim();
    if (t.length > 6000) return '${t.substring(0, 6000)}…';
    return t;
  }

  // ---------- istotne zdania ----------

  static const _abnormal = [
    'polip', 'gruczolak', 'adenoma', 'nadzerk', 'owrzodzen', 'wrzod', 'zapaleni', 'zapalny', 'przekrwien', 'obrzek', 'guz', 'nowotw', 'rak ', 'naciek',
    'podejrzen', 'torbiel', 'kamic', 'kamien', 'zlog', 'przerost', 'zwezen', 'poszerzen', 'tetniak', 'zakrzep', 'skrzeplin', 'migotani', 'trzepotani',
    'czestoskurcz', 'pauz', 'blok', 'niedomykaln', 'zwezenie zastawki', 'stluszczen', 'powieksz', 'uchylk', 'zylak', 'helicobacter', 'dysplazj',
    'metaplazj', 'barrett', 'refluks', 'przepuklin', 'hemoroid', 'guzki krwawnicze', 'krwawien', 'zmiana ogniskowa', 'zmiany ogniskowe',
    'zmiana', 'zmiany', 'patologi', 'nieprawidlow', 'hipokinez', 'akinez', 'niedokrwien', 'zawal', 'arytmi', 'ekstrasystol', 'pobudzenia komorowe',
    'pobudzen komorowych', 'salw', 'bigemin', 'osteopor', 'osteopeni', 'zwyrodnien', 'dyskopati', 'wysiek', 'plyn w', 'plynu w', 'zrost', 'bliznow', 'atrofi', 'zanik',
    'nadcisnien', 'guzek', 'guzki', 'zacm', 'jaskr', 'retinopati', 'zwyrodnienie plamki', 'odwarstwien', 'druzy', 'obrzek plamki',
    'zmetnieni', 'neowaskulary', 'krwotok', 'zakrzep zyly siatkowki', 'ubytki w polu widzenia', 'ubytek w polu widzenia', 'mikrozwapnien', 'birads 3', 'birads 4', 'birads 5', 'bi rads 3', 'bi rads 4', 'bi rads 5', 'tirads 4', 'tirads 5',
  ];

  static const _negations = [
    'nie stwierdz', 'nie stwierdzono', 'bez ', 'nie uwidoczn', 'nie wykazano', 'nie wykazuje', 'brak ', 'nie obserwuje', 'nie obserwowano',
    'nie zarejestrowano', 'nie wykryto', 'wykluczono', 'nie ma ', 'nieobecn', 'nie widac', 'nie stwierdza sie', 'w normie', 'prawidlow',
  ];

  static List<String> sentences(String text) {
    final t = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    return t
        .split(RegExp(r'(?<=[.;!?])\s+(?=[A-ZĄĆĘŁŃÓŚŹŻ0-9])|(?<=[.;])\s*-\s+'))
        .map((s) => s.trim())
        .where((s) => s.length >= 6)
        .toList();
  }

  static List<ReportFinding> findings(String text) {
    final out = <ReportFinding>[];
    for (final s in sentences(text)) {
      final n = ' ${normText(s)} ';
      final hits = <String>[];
      for (final w in _abnormal) {
        final i = n.indexOf(' $w');
        if (i < 0) continue;
        // zaprzeczenie przed słowem kluczowym w tym samym zdaniu (lub frazie po przecinku)
        final before = n.substring(0, i);
        final clause = before.contains(',') ? before.substring(before.lastIndexOf(',')) : before;
        final negated = _negations.any((ng) => clause.contains(ng));
        if (!negated) hits.add(w.trim());
      }
      // "zmiana"/"zmiany" są bardzo ogólne – liczą się tylko z innym słowem lub bez "bez zmian"
      final generic = {'zmiana', 'zmiany'};
      final specific = hits.where((h) => !generic.contains(h)).toList();
      final isAbn = specific.isNotEmpty || (hits.isNotEmpty && !n.contains(' bez zmian'));
      if (isAbn) out.add(ReportFinding(s, true, specific.isEmpty ? hits : specific));
    }
    return out.take(20).toList();
  }

  // ---------- termin kontroli ----------

  static final _fuRe = RegExp(
    r'(kontrol\w*|powt\w*|ponown\w*|kolejn\w*|nastepn\w*|zgloszeni\w*|badanie\s+\w+|wizyt\w*|surveillance)[^.\n]{0,60}?\b(za|po|w ciagu|co|przez)\s+(\d{1,2}|pol|rok|jeden|dwa|trzy|cztery|piec|szesc)\s*[-–]?\s*(\d{1,2})?\s*(lat|lata|rok|roku|mies\w*|m-c\w*|mc|tyg\w*|dni)',
  );

  static const _words = {'pol': 0.5, 'rok': 1, 'jeden': 1, 'dwa': 2, 'trzy': 3, 'cztery': 4, 'piec': 5, 'szesc': 6};

  /// Zwraca (termin, fragment zalecenia).
  static (DateTime, String)? followUp(String text, DateTime from) {
    final n = normText(text)
        .replaceAll(' za pol roku', ' za 6 miesiecy')
        .replaceAll(' po pol roku', ' po 6 miesiecy')
        .replaceAll(' za rok', ' za 1 rok')
        .replaceAll(' po roku', ' po 1 roku')
        .replaceAll(' co roku', ' co 1 rok');
    final m = _fuRe.firstMatch(n);
    if (m == null) {
      final d = RegExp(r'(kontrol\w*|powt\w*)[^.\n]{0,60}?(\d{1,2})\s(\d{1,2})\s(20\d{2})').firstMatch(n);
      if (d != null) {
        final dt = DateTime(int.parse(d.group(4)!), int.parse(d.group(3)!), int.parse(d.group(2)!));
        if (dt.month == int.parse(d.group(3)!)) return (dt, d.group(0)!);
      }
      return null;
    }
    final a = m.group(3)!;
    double v = double.tryParse(a) ?? (_words[a] ?? 1).toDouble();
    final unit = m.group(5)!;
    int days;
    if (unit.startsWith('lat') || unit.startsWith('rok')) {
      days = (v * 365).round();
    } else if (unit.startsWith('mies') || unit.startsWith('m')) {
      days = (v * 30.4).round();
    } else if (unit.startsWith('tyg')) {
      days = (v * 7).round();
    } else {
      days = v.round();
    }
    if (days <= 0 || days > 365 * 15) return null;
    return (from.add(Duration(days: days)), m.group(0)!);
  }
}
