// Parser tekstu wyników badań (z PDF lub OCR) -> lista parametrów z wartościami i normami.

import 'lab_dictionary.dart';
import 'text_utils.dart';

class ParsedResult {
  String key;
  String name;
  double? value;
  String? valueText;
  String unit;
  double? refLow, refHigh;
  String? flag; // 'H', 'L' lub null
  bool known;
  bool selected;
  final String rawLine;

  ParsedResult({
    required this.key,
    required this.name,
    this.value,
    this.valueText,
    this.unit = '',
    this.refLow,
    this.refHigh,
    this.flag,
    required this.known,
    this.selected = true,
    this.rawLine = '',
  });

  @override
  String toString() => '$key|$name|${value ?? valueText}|$unit|$refLow-$refHigh|$flag';
}

class ParseOutput {
  final List<ParsedResult> results;
  final DateTime? date;
  final String? facility;
  final String suggestedCategory;
  final String suggestedTitle;
  ParseOutput(this.results, this.date, this.facility, this.suggestedCategory, this.suggestedTitle);
}

class LabParser {
  static const _num = r'\d+(?:[.,]\d+)?';

  static final RegExp _numRe = RegExp(r'(?<![\p{L}\d.,/^])([<>≤≥]=?\s*)?(\d+(?:[.,]\d+)?)(?![\d])', unicode: true);

  static final RegExp _unitRe = RegExp(
    r'^(?:'
    r'(?:x\s?10\s?\^?\s?\d{1,2}|10\s?\^\s?\d{1,2}|10[³⁶⁹]|10¹²|tys\.?|mln\.?|[gkmt])\s?/\s?(?:[uµμp]l|l|mm3|mm³)'
    r'|ml\s?/\s?min(?:\s?/\s?1[,.]73\s?m(?:2|²|\^2)?)?'
    r'|mm\s?/\s?(?:1\s?)?(?:h|godz\.?)'
    r'|[munpµμ]?(?:g|mol|iu|ui|u|j|eq|kat)\s?/\s?(?:d?l|ml|l|g|dl)'
    r'|[munpµμ]?(?:iu|ui|u|j)\s?/\s?(?:ml|l)'
    r'|ud\.?\s?/\s?min|/\s?min|bpm|ms'
    r'|(?:au|ru|eu|ai|k?iu|ku)\s?/\s?(?:ml|l)|s/co|coi'
    r'|g/ml|l/l|fl|pg|%|‰|sek\.?|s|wpw\.?|ratio|indeks'
    r')(?![\p{L}\d])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _flagRe = RegExp(r'^\s*(?:\(\s*)?([HL]|[↑↓]|\*{1,2}|!+|\+|-)(?:\s*\))?(?![\p{L}\d])', unicode: true);

  static final RegExp _rangeTwo = RegExp('($_num)\\s*(?:-|–|—|÷|\\.\\.\\.?|do)\\s*($_num)');
  static final RegExp _rangeHigh = RegExp('(?:<=|<|≤|poniżej|ponizej|do)\\s*($_num)', caseSensitive: false);
  static final RegExp _rangeLow = RegExp('(?:>=|>|≥|powyżej|powyzej|od|min\\.?)\\s*($_num)', caseSensitive: false);

  static const _qualitative = [
    'ujemny', 'ujemne', 'ujemna', 'dodatni', 'dodatnie', 'dodatnia', 'nieobecne', 'nieobecny', 'obecne', 'obecny',
    'nie wykryto', 'wykryto', 'w normie', 'prawidłowy', 'prawidłowe', 'brak', 'pojedyncze', 'liczne', 'słomkowy', 'żółty',
    'przejrzysty', 'mętny', 'lekko mętny', 'reaktywny', 'niereaktywny',
  ];

  static const _unknownStop = [
    'data', 'wiek', 'pesel', 'tel', 'telefon', 'nr', 'numer', 'strona', 'str', 'godz', 'kod', 'ul', 'lat', 'zlecen',
    'pobran', 'urodzen', 'material', 'probk', 'adres', 'faks', 'fax', 'regon', 'nip', 'konto', 'cena', 'kwota', 'razem',
    'wydruk', 'lekarz', 'pacjent', 'ponizej', 'powyzej', 'stezenie', 'zalecane', 'dla', 'cukrzyca', 'prawidlowa', 'nieprawidlowa',
    'badanie', 'metoda', 'wartosc', 'wynik', 'id', 'zlecajacy', 'rejestr', 'autoryz', 'wykonan', 'przyjec', 'odbior', 'kod pocztowy',
  ];

  /// Zbiór dopasowań aliasów do zwiniętego tekstu linii.
  static (LabParam, int, int)? _matchAlias(String line) {
    LabDictionary.ensure();
    final n = normSameLength(line);
    // zwinięcie spacji z mapą indeksów do oryginału
    final collapsed = StringBuffer();
    final map = <int>[];
    var prevSpace = true;
    for (var i = 0; i < n.length; i++) {
      final c = n[i];
      if (c == ' ') {
        if (!prevSpace) {
          collapsed.write(' ');
          map.add(i);
        }
        prevSpace = true;
      } else {
        collapsed.write(c);
        map.add(i);
        prevSpace = false;
      }
    }
    final cs = collapsed.toString();
    if (cs.isEmpty) return null;

    // możliwe początki: 0 oraz po numeracji typu "1. " / "12) "
    final starts = <int>[0];
    final numbering = RegExp(r'^(\d{1,2}) ').firstMatch(cs);
    if (numbering != null) starts.add(numbering.end);
    // kody procedur ICD-9 na początku linii, np. "C55 Morfologia", "L43 TSH"
    final code = RegExp(r'^[a-z]\d{2,3} ').firstMatch(cs);
    if (code != null) starts.add(code.end);

    for (final st in starts) {
      for (final a in LabDictionary.aliases) {
        final al = a.key;
        if (cs.startsWith(al, st)) {
          final end = st + al.length;
          if (end == cs.length || cs[end] == ' ') {
            final origEnd = map[end - 1] + 1;
            return (a.value, origEnd, al.length);
          }
        }
      }
    }
    return null;
  }

  static String _clean(String s) =>
      s.replaceAll('\t', ' ').replaceAll(' ', ' ').replaceAll(RegExp(r'[ ]{2,}'), '  ').trimRight();

  /// Wyszukuje wartość, jednostkę, flagę i normę w tekście po nazwie parametru.
  static ParsedResult? _parseRest(String rest, {required String key, required String name, required bool known, required String raw, LabParam? param, int minScore = 0}) {
    final cands = _numRe.allMatches(rest).toList();
    if (cands.isEmpty) return null;

    RegExpMatch? best;
    var bestScore = -1;
    String unit = '';
    String? flag;
    int afterIdx = 0;
    for (final m in cands) {
      var pos = m.end;
      var score = 0;
      String u = '';
      String? fl;
      var tail = rest.substring(pos);
      var fm = _flagRe.firstMatch(tail);
      if (fm != null && fm.group(1) != '-' && fm.group(1) != '+') {
        fl = fm.group(1);
        pos += fm.end;
        tail = rest.substring(pos);
      }
      final lead = RegExp(r'^\s*').firstMatch(tail)!.end;
      final um = _unitRe.firstMatch(tail.substring(lead));
      if (um != null) {
        u = um.group(0)!;
        pos += lead + um.end;
        score += 2;
        tail = rest.substring(pos);
        if (fl == null) {
          fm = _flagRe.firstMatch(tail);
          if (fm != null && fm.group(1) != '-' && fm.group(1) != '+') {
            fl = fm.group(1);
            pos += fm.end;
            tail = rest.substring(pos);
          }
        }
      }
      if (_rangeTwo.firstMatch(tail) != null || _rangeHigh.hasMatch(tail) || _rangeLow.hasMatch(tail)) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = m;
        unit = u;
        flag = fl;
        afterIdx = pos;
      }
      if (score >= 3) break;
    }
    if (best == null) return null;
    if (!known && bestScore < 2) return null;
    if (bestScore < minScore) return null;
    // Za dużo tekstu między nazwą a liczbą = to raczej zdanie, nie wynik.
    final gapLetters = RegExp(r'\p{L}', unicode: true).allMatches(rest.substring(0, best.start).replaceAll(RegExp(r'\([^)]*\)'), '')).length;
    if (gapLetters > (bestScore == 0 ? 12 : 40)) return null;

    final value = parseNum(best.group(2)!);
    final cmp = best.group(1)?.trim();
    final between = rest.substring(0, best.start);
    final tail = rest.substring(afterIdx);

    double? lo, hi;
    final r2 = _rangeTwo.firstMatch(tail);
    if (r2 != null) {
      lo = parseNum(r2.group(1)!);
      hi = parseNum(r2.group(2)!);
      if (lo != null && hi != null && lo > hi) {
        final t = lo;
        lo = hi;
        hi = t;
      }
    } else {
      final rh = _rangeHigh.firstMatch(tail);
      final rl = _rangeLow.firstMatch(tail);
      if (rh != null && (rl == null || rh.start <= rl.start)) {
        hi = parseNum(rh.group(1)!);
      } else if (rl != null) {
        lo = parseNum(rl.group(1)!);
      }
    }
    // Jednostka czasem stoi dopiero po normie: "14,2  13,5-18,0  g/dl"
    if (unit.isEmpty) {
      final afterRange = r2 != null ? tail.substring(r2.end) : '';
      final lead = RegExp(r'^\s*').firstMatch(afterRange)!.end;
      final um = _unitRe.firstMatch(afterRange.substring(lead));
      if (um != null) unit = um.group(0)!;
    }

    var k = key;
    var nm = name;
    var p = param;
    if (p != null) {
      final percent = unit.trim() == '%' || between.contains('%');
      final absolute = between.contains('#');
      final r = LabDictionary.resolve(p, percent && !absolute);
      k = r.key;
      nm = r.name;
      p = r;
    }

    if (flag == null || flag.startsWith('*')) {
      final end = RegExp(r'(?:^|\s)(H|L|↑|↓)\s*\**\s*$').firstMatch(tail);
      if (end != null) flag = end.group(1);
    }
    String? f;
    if (flag != null) {
      if (flag == 'H' || flag == '↑') f = 'H';
      if (flag == 'L' || flag == '↓') f = 'L';
    }
    if (cmp != null && cmp.isNotEmpty) {
      // "<0,5" – wartość poniżej progu oznaczalności; zapisujemy tekstowo i liczbowo
      return ParsedResult(
          key: k, name: nm, value: value, valueText: '$cmp${best.group(2)}', unit: unit.trim(), refLow: lo, refHigh: hi, flag: f, known: known, rawLine: raw);
    }
    return ParsedResult(key: k, name: nm, value: value, unit: unit.trim(), refLow: lo, refHigh: hi, flag: f, known: known, rawLine: raw);
  }

  static ParsedResult? parseLine(String line, {String? next, void Function()? consumeNext}) {
    final l = _clean(line);
    if (l.trim().length < 2) return null;
    final m = _matchAlias(l);
    if (m != null) {
      final (param, end, aliasLen) = m;
      final rest = l.substring(end);
      final minScore = aliasLen <= 3 ? 1 : 0;
      var r = _parseRest(rest, key: param.key, name: param.name, known: true, raw: l, param: param, minScore: minScore);
      if (r != null) return r;
      // tylko nazwa w linii – wartość w kolejnej
      final restLetters = RegExp(r'[\p{L}\d]', unicode: true).allMatches(rest).length;
      if (restLetters <= 12 && next != null) {
        r = _parseRest('$rest  ${_clean(next)}', key: param.key, name: param.name, known: true, raw: '$l | $next', param: param, minScore: 1);
        if (r != null) {
          consumeNext?.call();
          return r;
        }
      }
      // wynik jakościowy
      final rn = rest.toLowerCase();
      for (final q in _qualitative) {
        final i = rn.indexOf(q);
        if (i >= 0 && i < 40) {
          return ParsedResult(key: param.key, name: param.name, valueText: q, known: true, rawLine: l, selected: false);
        }
      }
      return null;
    }
    return _parseUnknown(l);
  }

  static final RegExp _unknownRe = RegExp(r'^\s*([\p{L}][\p{L}\d \-\(\),./%#]{1,60}?)\s*:?\s+(?=[<>≤≥]?=?\s*\d)', unicode: true);

  static ParsedResult? _parseUnknown(String l) {
    final m = _unknownRe.firstMatch(l);
    if (m == null) return null;
    var name = m.group(1)!.trim().replaceAll(RegExp(r'[\s\-:.,]+$'), '');
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(name).length;
    if (letters < 3) return null;
    final nn = normText(name);
    for (final s in _unknownStop) {
      if (nn == s || nn.startsWith('$s ') || nn.contains(' $s')) return null;
    }
    final r = _parseRest(l.substring(m.end), key: 'X:$nn', name: name, known: false, raw: l);
    if (r == null) return null;
    if (r.unit.isEmpty) return null;
    // bez normy to zwykle zdanie z opisu ("Poniżej 130 mg/dl dla osób…"), nie wynik
    if (r.refLow == null && r.refHigh == null) return null;
    return r;
  }

  static ParseOutput parse(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final out = <ParsedResult>[];
    final seen = <String>{};
    final lineOf = Map<ParsedResult, int>.identity();
    var i = 0;
    while (i < lines.length) {
      var skip = false;
      final r = parseLine(lines[i], next: i + 1 < lines.length ? lines[i + 1] : null, consumeNext: () => skip = true);
      if (r != null && !seen.contains(r.key)) {
        seen.add(r.key);
        out.add(r);
        lineOf[r] = skip ? i + 1 : i;
      }
      i += skip ? 2 : 1;
    }
    // Norma w kolejnych wierszach: "< 20 AU/ml wynik negatywny", "≥ 20 AU/ml wynik pozytywny"
    final negRe = RegExp('(<|≤|<=|poniżej|ponizej|do)\\s*($_num)[^\\n]{0,25}(negatyw|ujemn|prawid|w normie|brak)', caseSensitive: false);
    final posRe = RegExp('(≥|>=|>|powyżej|powyzej|od)\\s*($_num)[^\\n]{0,25}(pozytyw|dodatn)', caseSensitive: false);
    for (final r in out) {
      if (r.refLow != null || r.refHigh != null) continue;
      final k = lineOf[r];
      if (k == null) continue;
      for (var j = k + 1; j < lines.length && j <= k + 3; j++) {
        if (normText(lines[j]).isEmpty) continue;
        final neg = negRe.firstMatch(lines[j]);
        final pos = posRe.firstMatch(lines[j]);
        if (neg != null) {
          r.refHigh = parseNum(neg.group(2)!);
          break;
        }
        if (pos != null) {
          r.refHigh = parseNum(pos.group(2)!);
          break;
        }
        // kolejny parametr – przestajemy szukać
        if (_matchAlias(lines[j]) != null) break;
      }
    }
    // Nazwy badań z nagłówków laboratorium: "Morfologia krwi (ICD-9: C55)"
    final headers = <String>[];
    for (final l in lines) {
      final m = RegExp(r'^\s*(.{3,120}?)\s*\(\s*ICD-?\s*9\s*:?\s*[A-Z]\d{2}\s*\)', caseSensitive: false).firstMatch(l);
      if (m == null) continue;
      var h = m.group(1)!.trim();
      h = h.replaceAll(RegExp(r'\s+met\.?\s+\S+$', caseSensitive: false), '').trim();
      if (h.length > 2 && !headers.contains(h)) headers.add(h);
    }
    final date = findDate(text);
    final fac = findFacility(text);
    final cats = <String, int>{};
    for (final r in out.where((r) => r.known)) {
      final c = LabDictionary.get(r.key)?.category ?? LabDictionary.inne;
      cats[c] = (cats[c] ?? 0) + 1;
    }
    String category;
    String title;
    if (out.any((r) => r.known) || headers.isNotEmpty) {
      category = DocCategories.lab;
      final sorted = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      title = headers.isNotEmpty ? _shortTitle(headers) : sorted.take(3).map((e) => e.key).join(', ');
    } else {
      category = guessCategory(text);
      title = guessTitle(text, category);
    }
    return ParseOutput(out, date, fac, category, title);
  }

  static String _shortTitle(List<String> h) {
    var t = h.take(3).join(', ');
    if (h.length > 3) t += ' i inne';
    if (t.length > 90) t = '${t.substring(0, 88)}…';
    return t;
  }

  static DateTime? findDate(String text) {
    final res = <(DateTime, int, int)>[];
    final now = DateTime.now();
    void add(int y, int mo, int d, int pos) {
      if (y < 1990 || y > now.year + 1 || mo < 1 || mo > 12 || d < 1 || d > 31) return;
      final dt = DateTime(y, mo, d);
      if (dt.month != mo) return;
      final lineStart = text.lastIndexOf('\n', pos > 0 ? pos - 1 : 0) + 1;
      var ctx = normText(text.substring(lineStart > pos - 40 ? lineStart : pos - 40, pos));
      if (!RegExp(r'[a-z]{3}').hasMatch(ctx) && lineStart > 1) {
        final prevStart = text.lastIndexOf('\n', lineStart - 2) + 1;
        ctx = normText(text.substring(prevStart, lineStart));
      }
      var score = 0;
      if (ctx.contains('pobran')) score += 5;
      if (ctx.contains('wykonan') || ctx.contains('badani')) score += 3;
      if (ctx.contains('przyjec') || ctx.contains('rejestr')) score += 2;
      if (ctx.contains('zatwierdz') || ctx.contains('autoryz') || ctx.contains('wydan')) score += 1;
      if (ctx.contains('wydruk') || ctx.contains('druk')) score -= 1;
      if (ctx.contains('urodz')) score -= 20;
      if (dt.isAfter(now.add(const Duration(days: 1)))) score -= 10;
      res.add((dt, score, pos));
    }

    for (final m in RegExp(r'(?<!\d)(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})(?!\d)').allMatches(text)) {
      add(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!), m.start);
    }
    for (final m in RegExp(r'(?<!\d)(\d{4})[.\-/](\d{2})[.\-/](\d{2})(?!\d)').allMatches(text)) {
      add(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), m.start);
    }
    if (res.isEmpty) return null;
    res.sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
    if (res.first.$2 < -5) return null;
    return res.first.$1;
  }

  static const _facilities = [
    ('diagnostyka', 'Diagnostyka'),
    ('alab', 'ALAB laboratoria'),
    ('synevo', 'Synevo'),
    ('lux med', 'LUX MED'),
    ('luxmed', 'LUX MED'),
    ('medicover', 'Medicover'),
    ('enel med', 'Enel-Med'),
    ('enelmed', 'Enel-Med'),
    ('synlab', 'Synlab'),
    ('cm damiana', 'Centrum Medyczne Damiana'),
    ('bruss', 'Bruss'),
    ('salve', 'Salve'),
    ('affidea', 'Affidea'),
    ('voxel', 'Voxel'),
    ('helimed', 'Helimed'),
    ('falck', 'Falck'),
    ('medica', 'Medica'),
  ];

  static String? findFacility(String text) {
    final n = ' ${normText(text.length > 3000 ? text.substring(0, 3000) : text)} ';
    for (final f in _facilities) {
      if (n.contains(' ${f.$1} ')) return f.$2;
    }
    final m = RegExp(r'(Laboratorium[^\n]{3,50}|Szpital[^\n]{3,60}|Przychodnia[^\n]{3,50})').firstMatch(text);
    return m?.group(1)?.trim();
  }

  static String guessCategory(String text) {
    final n = ' ${normText(text)} ';
    bool has(List<String> w) => w.any((x) => n.contains(' $x'));
    if (has(['usg', 'ultrasonograf', 'rtg', 'rentgen', 'tomografi', 'rezonans', 'mammograf', 'densytometri', 'echo serca', 'echokardiograf', 'badanie obrazowe'])) {
      return DocCategories.imaging;
    }
    if (has(['ekg', 'elektrokardiogra', 'holter', 'spirometri', 'audiometri', 'eeg', 'emg'])) return DocCategories.functional;
    if (has(['wypis', 'karta informacyjna', 'epikryza', 'konsultac', 'porada', 'wizyta', 'zalecenia', 'rozpoznanie'])) return DocCategories.visit;
    if (has(['szczepien', 'szczepionk'])) return DocCategories.vaccine;
    if (has(['recepta', 'skierowanie'])) return DocCategories.prescription;
    if (has(['wynik', 'norma', 'zakres referencyjny', 'laboratori'])) return DocCategories.lab;
    return DocCategories.other;
  }

  static String guessTitle(String text, String category) {
    final n = normText(text);
    const known = [
      ('usg jamy brzusznej', 'USG jamy brzusznej'),
      ('usg tarczycy', 'USG tarczycy'),
      ('usg piersi', 'USG piersi'),
      ('usg', 'USG'),
      ('rtg klatki', 'RTG klatki piersiowej'),
      ('rtg', 'RTG'),
      ('tomografia', 'Tomografia komputerowa'),
      ('rezonans', 'Rezonans magnetyczny'),
      ('mammografia', 'Mammografia'),
      ('echo serca', 'Echo serca'),
      ('echokardiografia', 'Echo serca'),
      ('holter', 'Holter'),
      ('ekg', 'EKG'),
      ('spirometria', 'Spirometria'),
      ('karta informacyjna', 'Karta informacyjna'),
      ('wypis', 'Wypis ze szpitala'),
      ('konsultacja', 'Konsultacja'),
      ('badanie ogolne moczu', 'Badanie ogólne moczu'),
      ('morfologia', 'Morfologia'),
    ];
    for (final k in known) {
      if (n.contains(k.$1)) return k.$2;
    }
    return category;
  }
}

class DocCategories {
  static const lab = 'Badania laboratoryjne';
  static const imaging = 'Badania obrazowe';
  static const functional = 'EKG i badania czynnościowe';
  static const visit = 'Wizyty i wypisy';
  static const prescription = 'Recepty i skierowania';
  static const vaccine = 'Szczepienia';
  static const endoscopy = 'Endoskopia';
  static const histo = 'Histopatologia i cytologia';
  static const other = 'Inne';
  static const all = [lab, imaging, endoscopy, functional, histo, visit, prescription, vaccine, other];
}
