// Badania wzroku: ostrość wzroku, refrakcja (SPH/CYL/AX/ADD), ciśnienie wewnątrzgałkowe,
// biometria (długość osiowa, keratometria), pachymetria, OCT, pole widzenia – osobno dla oka prawego i lewego.

import 'lab_dictionary.dart';
import 'lab_parser.dart';
import 'text_utils.dart';

class _Label {
  final String m; // pomiar
  final RegExp re;
  _Label(this.m, String pattern) : re = RegExp(pattern, caseSensitive: false, unicode: true);
}

class EyeParser {
  static final _labels = <_Label>[
    _Label('VACC', r'(?:visus|vis\.?|va|ostro[sś][cć]\s+wzroku|ow)\s*(?:do\s+dali\s*)?(?:z\s+korekcj[aąi]\w*|w\s+korekcji|cc|c\.c\.|skorygowan\w*|bcva)'),
    _Label('VAN', r'(?:visus|vis\.?|va|ostro[sś][cć]\s+wzroku)\s*(?:do\s+)?bli[zż]\w*|\bnva\b'),
    _Label('VA', r'(?:visus|vis\.?|\bva\b|ostro[sś][cć]\s+wzroku|\bow\b|\bucva\b)\s*(?:do\s+dali\s*)?(?:bez\s+korekcji|sc|s\.c\.|nieskorygowan\w*)?'),
    _Label('SPH', r'\b(?:sph|sfera|sfer\w*|sf)\b'),
    _Label('CYL', r'\b(?:cyl|cylinder|cyl\w*)\b'),
    _Label('AX', r'\b(?:ax|axis|o[sś]\s+cylindra)\b|(?<![\p{L}])oś(?![\p{L}])'),
    _Label('ADD', r'\b(?:add|addycja)\b'),
    _Label('IOP', r'\b(?:iop|tonometri\w*|tensja|nct|tono\w*)\b|ci[sś]nienie\s+(?:wewn[aą]trzga[lł]kowe|w\s+oku|oczne|´?wewn)'),
    _Label('AL', r'\bal\b|\baxl\b|d[lł]ugo[sś][cć]\s+(?:osiowa|ga[lł]ki|osi)|axial\s+length'),
    _Label('CCT', r'pachymetri\w*|\bcct\b|grubo[sś][cć]\s+rog[oó]wki'),
    _Label('K1', r'\bk1\b|\bkf\b'),
    _Label('K2', r'\bk2\b|\bks\b'),
    _Label('RNFL', r'\brnfl\b'),
    _Label('CMT', r'\bcmt\b|\bcst\b|grubo[sś][cć]\s+(?:centraln\w+\s+)?siatk[oó]wki|centraln\w+\s+grubo[sś][cć]'),
    _Label('MD', r'\bmd\b'),
    _Label('CD', r'\bc\s*/\s*d\b|stosunek\s+c\s*/?\s*d|cup\s*/\s*disc'),
    _Label('PD', r'\bpd\b|rozstaw\s+[zź]renic|odleg[lł]o[sś][cć]\s+mi[eę]dzy[zź]reniczn\w*'),
  ];

  static final _right = RegExp(r'(?<![\p{L}])(?:OP|OD|RE|R(?=\s*[:=])|P(?=\s*[:=]))(?![\p{L}])|\b(?:oko\s+prawe|prawe\s+oko|prawe|prawy|right)\b', unicode: true, caseSensitive: true);
  static final _rightCi = RegExp(r'\b(?:oko\s+prawe|prawe\s+oko|prawe|prawy|right)\b', caseSensitive: false);
  static final _left = RegExp(r'(?<![\p{L}])(?:OL|OS|LE|L(?=\s*[:=]))(?![\p{L}])', unicode: true, caseSensitive: true);
  static final _leftCi = RegExp(r'\b(?:oko\s+lewe|lewe\s+oko|lewe|lewy|left)\b', caseSensitive: false);

  static final _val = RegExp(r'(?<![\p{L}\d])([+\-−–—]?\s?\d{1,3}(?:[.,]\d{1,2})?(?:\s*/\s*\d{1,3}(?:[.,]\d)?)?)(?![\d])|\b(pl(?:ano)?)\b', unicode: true, caseSensitive: false);

  static const _keywords = [
    'okulist', 'refrakcj', 'autorefrakt', 'ostrosc wzroku', 'visus', 'tonometri', 'cisnienie wewnatrzgalkowe', 'pole widzenia', 'perymetri',
    'keratometri', 'biometri', 'pachymetri', 'dno oka', 'oko prawe', 'oko lewe', 'okulary', 'soczewk', ' sph ', ' cyl ', 'rnfl', 'oct ',
  ];

  static bool looksLikeEye(String text) {
    final n = ' ${normText(text)} ';
    var hits = 0;
    for (final k in _keywords) {
      if (n.contains(k)) hits++;
    }
    final markers = RegExp(r'(?<![\p{L}])(OP|OL|OD|OS)(?![\p{L}])', unicode: true).allMatches(text).length;
    return hits >= 2 || (hits >= 1 && markers >= 2);
  }

  static double? _num(String raw, String m) {
    var s = raw.replaceAll(RegExp(r'\s'), '').replaceAll(RegExp('[−–—]'), '-');
    if (RegExp(r'^pl', caseSensitive: false).hasMatch(s)) return 0;
    if (s.contains('/')) {
      if (!m.startsWith('VA')) return null;
      final p = s.split('/');
      final a = parseNum(p[0]), b = parseNum(p[1]);
      if (a == null || b == null || b == 0) return null;
      return double.parse((a / b).toStringAsFixed(2));
    }
    final v = parseNum(s);
    // myślnik jako separator ("OP - 1,0") – znak ma sens tylko dla sfery, cylindra i MD
    if (v != null && v < 0 && !const {'SPH', 'CYL', 'MD'}.contains(m)) return -v;
    return v;
  }

  static bool _valid(String m, double v) {
    switch (m) {
      case 'VA':
      case 'VACC':
      case 'VAN':
        return v >= 0 && v <= 2.5;
      case 'SPH':
        return v >= -30 && v <= 30;
      case 'CYL':
        return v >= -10 && v <= 10;
      case 'AX':
        return v >= 0 && v <= 180 && v == v.roundToDouble();
      case 'ADD':
        return v > 0 && v <= 4;
      case 'IOP':
        return v >= 3 && v <= 70;
      case 'AL':
        return v >= 17 && v <= 36;
      case 'CCT':
        return v >= 350 && v <= 750;
      case 'K1':
      case 'K2':
        return v >= 35 && v <= 60;
      case 'RNFL':
      case 'CMT':
        return v >= 20 && v <= 700;
      case 'MD':
        return v >= -40 && v <= 6;
      case 'CD':
        return v >= 0 && v <= 1;
      case 'PD':
        return v >= 40 && v <= 85;
    }
    return false;
  }

  static List<(int, String)> _labelsIn(String s) {
    final out = <(int, String)>[];
    final taken = <int>[];
    for (final l in _labels) {
      for (final m in l.re.allMatches(s)) {
        if (taken.any((t) => (t - m.start).abs() < 3)) continue;
        taken.add(m.start);
        out.add((m.end, l.m));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  static List<(int, int, String)> _markers(String line) {
    final out = <(int, int, String)>[];
    for (final m in _right.allMatches(line)) {
      out.add((m.start, m.end, 'R'));
    }
    for (final m in _rightCi.allMatches(line)) {
      if (!out.any((o) => o.$1 == m.start)) out.add((m.start, m.end, 'R'));
    }
    for (final m in _left.allMatches(line)) {
      out.add((m.start, m.end, 'L'));
    }
    for (final m in _leftCi.allMatches(line)) {
      if (!out.any((o) => o.$1 == m.start)) out.add((m.start, m.end, 'L'));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  static List<ParsedResult> parse(String text) {
    final res = <String, ParsedResult>{};
    void put(String m, String? side, double v, String raw, String line) {
      if (!_valid(m, v)) return;
      final key = side == null ? 'EYE_$m' : 'EYE_${m}_$side';
      final p = LabDictionary.get(key);
      if (p == null || res.containsKey(key)) return;
      final isFrac = raw.contains('/');
      res[key] = ParsedResult(
        key: key,
        name: p.name,
        value: v,
        valueText: isFrac ? raw.replaceAll(' ', '') : null,
        unit: p.unit,
        known: true,
        rawLine: line,
      );
    }

    List<String>? columns;
    String? ctx;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.replaceAll('\t', ' ');
      if (line.trim().isEmpty) continue;
      final markers = _markers(line);
      final labels = _labelsIn(line);
      final vals = _val.allMatches(line).toList();

      if (markers.isEmpty) {
        final distinct = labels.map((e) => e.$2).toSet();
        // nagłówek tabeli: "SPH CYL AX ADD"
        if (distinct.length >= 2 && vals.where((v) => (v.group(1) ?? '').contains(RegExp(r'[.,]'))).isEmpty) {
          columns = labels.map((e) => e.$2).toList();
          ctx = null;
          continue;
        }
        if (labels.isNotEmpty && vals.isEmpty) {
          ctx = labels.first.$2;
          columns = null;
          continue;
        }
        // "PD 62 mm", "IOP 15/17 mmHg"
        if (labels.isNotEmpty && vals.isNotEmpty) {
          final m = labels.first.$2;
          final after = vals.where((v) => v.start >= labels.first.$1).toList();
          if (m == 'PD' && after.isNotEmpty) {
            final v = _num(after.first.group(0)!, m);
            if (v != null) put(m, null, v, after.first.group(0)!, line);
          } else if (after.length == 1 && (after.first.group(1) ?? '').contains('/') && m == 'IOP') {
            final p = after.first.group(1)!.split('/');
            final a = parseNum(p[0]), b = parseNum(p[1]);
            if (a != null) put(m, 'R', a, p[0], line);
            if (b != null) put(m, 'L', b, p[1], line);
          }
        }
        continue;
      }

      // kontekst przed pierwszym oznaczeniem oka, np. "Tonometria: OP 15 OL 17"
      final prefixLabels = labels.where((l) => l.$1 <= markers.first.$1 + 1).map((e) => e.$2).toList();
      for (var i = 0; i < markers.length; i++) {
        final side = markers[i].$3;
        final start = markers[i].$2;
        final end = i + 1 < markers.length ? markers[i + 1].$1 : line.length;
        if (end <= start) continue;
        final seg = line.substring(start, end);
        final segLabels = _labelsIn(seg);
        final segVals = _val.allMatches(seg).toList();
        if (segVals.isEmpty) continue;
        if (segLabels.isNotEmpty) {
          for (var j = 0; j < segLabels.length; j++) {
            final from = segLabels[j].$1;
            final to = j + 1 < segLabels.length ? segLabels[j + 1].$1 : seg.length;
            final v = segVals.where((x) => x.start >= from && x.start < to).firstOrNull;
            if (v == null) continue;
            final n = _num(v.group(0)!, segLabels[j].$2);
            if (n != null) put(segLabels[j].$2, side, n, v.group(0)!, line);
          }
          continue;
        }
        final order = prefixLabels.length >= 2
            ? prefixLabels
            : (columns ?? (prefixLabels.isNotEmpty ? prefixLabels : (ctx != null ? [ctx] : <String>[])));
        for (var j = 0; j < order.length && j < segVals.length; j++) {
          final n = _num(segVals[j].group(0)!, order[j]);
          if (n != null) put(order[j], side, n, segVals[j].group(0)!, line);
        }
      }
    }
    // ekwiwalent sferyczny
    for (final s in const ['R', 'L']) {
      final sph = res['EYE_SPH_$s']?.value, cyl = res['EYE_CYL_$s']?.value;
      if (sph != null && cyl != null && !res.containsKey('EYE_SE_$s')) {
        final p = LabDictionary.get('EYE_SE_$s')!;
        res['EYE_SE_$s'] = ParsedResult(key: p.key, name: p.name, value: sph + cyl / 2, unit: p.unit, known: true, rawLine: 'SPH + CYL/2');
      }
    }
    return res.values.toList();
  }
}
