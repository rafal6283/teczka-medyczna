// Analiza zmian parametrów w czasie: serie, statystyki, trendy i wnioski.

import 'dart:math';

import '../data/models.dart';
import '../parse/lab_dictionary.dart';
import '../parse/text_utils.dart';

class SeriesPoint {
  final DateTime date;
  final double value;
  final double? low, high;
  final LabResult src;
  SeriesPoint(this.date, this.value, this.low, this.high, this.src);

  /// -1 poniżej normy, 0 w normie, 1 powyżej, null – brak normy
  int? get status {
    if (low != null && value < low! - 1e-9) return -1;
    if (high != null && value > high! + 1e-9) return 1;
    if (low != null || high != null) return 0;
    if (src.flag == 'H') return 1;
    if (src.flag == 'L') return -1;
    return null;
  }
}

class ParamStats {
  final int n;
  final double min, max, mean, first, last;
  final double? prev;
  final double? changeAbs, changePct; // ostatni vs poprzedni
  final double? totalPct; // ostatni vs pierwszy
  final double? slopePerYear, slopePctPerYear;
  final int outCount;
  final int trend; // -1 spada, 0 stabilnie, 1 rośnie
  final int spanDays;

  ParamStats({
    required this.n,
    required this.min,
    required this.max,
    required this.mean,
    required this.first,
    required this.last,
    this.prev,
    this.changeAbs,
    this.changePct,
    this.totalPct,
    this.slopePerYear,
    this.slopePctPerYear,
    required this.outCount,
    required this.trend,
    required this.spanDays,
  });
}

class ParamSeries {
  final String key;
  final String name;
  final String category;
  final String unit;
  final bool known;
  final List<SeriesPoint> points;
  final List<LabResult> textResults;
  final List<LabResult> skipped; // wyniki w nieprzeliczalnych jednostkach
  ParamStats? stats;

  ParamSeries(this.key, this.name, this.category, this.unit, this.known, this.points, this.textResults, this.skipped) {
    stats = _computeStats(points);
  }

  SeriesPoint? get latest => points.isEmpty ? null : points.last;
  DateTime? get lastDate {
    DateTime? d = points.isEmpty ? null : points.last.date;
    for (final t in textResults) {
      if (d == null || t.date.isAfter(d)) d = t.date;
    }
    return d;
  }

  double? get refLow => latest?.low;
  double? get refHigh => latest?.high;

  String get refText => refString(refLow, refHigh);
}

String refString(double? lo, double? hi) {
  if (lo != null && hi != null) return '${fmtNum(lo)}–${fmtNum(hi)}';
  if (hi != null) return '≤ ${fmtNum(hi)}';
  if (lo != null) return '≥ ${fmtNum(lo)}';
  return 'brak normy';
}

ParamStats? _computeStats(List<SeriesPoint> pts) {
  if (pts.isEmpty) return null;
  final vals = pts.map((e) => e.value).toList();
  final n = vals.length;
  final mean = vals.reduce((a, b) => a + b) / n;
  final last = vals.last;
  final prev = n >= 2 ? vals[n - 2] : null;
  double? pct(double a, double b) => b.abs() < 1e-12 ? null : (a - b) / b.abs() * 100;
  final spanDays = pts.last.date.difference(pts.first.date).inDays;

  double? slope;
  double? slopePct;
  if (n >= 3 && spanDays >= 30) {
    final t0 = pts.first.date.millisecondsSinceEpoch;
    final xs = pts.map((e) => (e.date.millisecondsSinceEpoch - t0) / (365.25 * 86400000)).toList();
    final mx = xs.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (xs[i] - mx) * (vals[i] - mean);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    if (sxx > 0) {
      slope = sxy / sxx;
      slopePct = mean.abs() < 1e-12 ? null : slope / mean.abs() * 100;
    }
  }

  var trend = 0;
  if (slopePct != null) {
    // trend liczony z regresji; dla krótkich serii wymagamy wyraźniejszej zmiany
    final thr = n >= 5 ? 5.0 : 8.0;
    if (slopePct > thr) trend = 1;
    if (slopePct < -thr) trend = -1;
  } else if (prev != null) {
    final c = pct(last, prev);
    if (c != null && c > 5) trend = 1;
    if (c != null && c < -5) trend = -1;
  }

  return ParamStats(
    n: n,
    min: vals.reduce(min),
    max: vals.reduce(max),
    mean: mean,
    first: vals.first,
    last: last,
    prev: prev,
    changeAbs: prev == null ? null : last - prev,
    changePct: prev == null ? null : pct(last, prev),
    totalPct: n >= 2 ? pct(last, vals.first) : null,
    slopePerYear: slope,
    slopePctPerYear: slopePct,
    outCount: pts.where((p) => (p.status ?? 0) != 0).length,
    trend: trend,
    spanDays: spanDays,
  );
}

class Analysis {
  /// Grupuje wyniki profilu w serie parametrów, ujednolicając jednostki.
  static List<ParamSeries> build(List<LabResult> results, {String? sex}) {
    final byKey = <String, List<LabResult>>{};
    for (final r in results) {
      byKey.putIfAbsent(r.key, () => []).add(r);
    }
    final out = <ParamSeries>[];
    byKey.forEach((key, list) {
      list.sort((a, b) => a.date.compareTo(b.date));
      final param = LabDictionary.get(key);
      final pts = <SeriesPoint>[];
      final texts = <LabResult>[];
      final skipped = <LabResult>[];
      String unit;
      if (param != null) {
        unit = param.unit;
        final dLow = param.lowFor(sex), dHigh = param.highFor(sex);
        for (final r in list) {
          if (r.value == null) {
            texts.add(r);
            continue;
          }
          final v = param.toBase(r.value!, r.unit);
          if (v == null) {
            skipped.add(r);
            continue;
          }
          final hasOwn = r.refLow != null || r.refHigh != null;
          final lo = hasOwn ? (r.refLow == null ? null : param.toBase(r.refLow!, r.unit)) : dLow;
          final hi = hasOwn ? (r.refHigh == null ? null : param.toBase(r.refHigh!, r.unit)) : dHigh;
          pts.add(SeriesPoint(r.date, v, lo, hi, r));
        }
        // jeśli nic nie dało się przeliczyć, pokaż w jednostce najczęstszej
        if (pts.isEmpty && skipped.isNotEmpty) {
          final u = _mostCommonUnit(skipped);
          unit = u;
          for (final r in List.of(skipped)) {
            if (normUnit(r.unit) == normUnit(u)) {
              pts.add(SeriesPoint(r.date, r.value!, r.refLow, r.refHigh, r));
              skipped.remove(r);
            }
          }
        }
      } else {
        final withVal = list.where((r) => r.value != null).toList();
        texts.addAll(list.where((r) => r.value == null));
        unit = withVal.isEmpty ? '' : _mostCommonUnit(withVal);
        for (final r in withVal) {
          if (normUnit(r.unit) == normUnit(unit)) {
            pts.add(SeriesPoint(r.date, r.value!, r.refLow, r.refHigh, r));
          } else {
            skipped.add(r);
          }
        }
      }
      final name = param?.name ?? list.last.name;
      final cat = param?.category ?? LabDictionary.inne;
      out.add(ParamSeries(key, name, cat, unit, param != null, pts, texts, skipped));
    });
    out.sort((a, b) {
      final ca = LabDictionary.categoryOrder.indexOf(a.category), cb = LabDictionary.categoryOrder.indexOf(b.category);
      if (ca != cb) return ca.compareTo(cb);
      if (a.known && b.known) {
        final keys = LabDictionary.byKey.keys.toList();
        return keys.indexOf(a.key).compareTo(keys.indexOf(b.key));
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  static String _mostCommonUnit(List<LabResult> l) {
    final c = <String, int>{};
    for (final r in l) {
      c[r.unit] = (c[r.unit] ?? 0) + 1;
    }
    return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }
}

enum InsightKind { alert, warning, good, info }

class Insight {
  final InsightKind kind;
  final String title;
  final String text;
  final String? paramKey;
  Insight(this.kind, this.title, this.text, {this.paramKey});
}

class Insights {
  static String _statusWord(int s) => s > 0 ? 'powyżej normy' : 'poniżej normy';

  static List<Insight> forSeries(List<ParamSeries> series) {
    final out = <Insight>[];
    final now = DateTime.now();
    for (final s in series) {
      final st = s.stats;
      final last = s.latest;
      if (st == null || last == null) continue;
      final u = s.unit.isEmpty ? '' : ' ${s.unit}';
      final lastStatus = last.status ?? 0;
      final prevPoint = s.points.length >= 2 ? s.points[s.points.length - 2] : null;
      final prevStatus = prevPoint?.status ?? 0;
      final ago = now.difference(last.date).inDays;

      if (lastStatus != 0) {
        final rep = _consecutiveOut(s.points, lastStatus);
        var t = '${fmtNum(last.value)}$u (${fmtDate(last.date)}), norma ${refString(last.low, last.high)}.';
        if (rep >= 2) t += ' To już $rep. wynik z rzędu ${_statusWord(lastStatus)}.';
        if (prevPoint != null && prevStatus == 0) t += ' Poprzednio w normie (${fmtNum(prevPoint.value)}).';
        if (st.trend != 0 && st.n >= 3) {
          final better = (st.trend < 0 && lastStatus > 0) || (st.trend > 0 && lastStatus < 0);
          t += better ? ' Trend zmierza w stronę normy.' : ' Trend oddala od normy.';
        }
        out.add(Insight(ago > 365 ? InsightKind.warning : InsightKind.alert, '${s.name}: ${_statusWord(lastStatus)}', t, paramKey: s.key));
        continue;
      }

      if (prevPoint != null && prevStatus != 0) {
        out.add(Insight(InsightKind.good, '${s.name}: wrócił do normy',
            '${fmtNum(prevPoint.value)} → ${fmtNum(last.value)}$u (norma ${refString(last.low, last.high)}).',
            paramKey: s.key));
        continue;
      }

      // w normie, ale tempo zmian sugeruje wyjście poza normę w ciągu roku
      if (st.slopePerYear != null && st.n >= 3) {
        final proj = last.value + st.slopePerYear!;
        final willHigh = last.high != null && proj > last.high! && st.slopePerYear! > 0;
        final willLow = last.low != null && proj < last.low! && st.slopePerYear! < 0;
        if (willHigh || willLow) {
          out.add(Insight(InsightKind.warning, '${s.name}: zbliża się do granicy normy',
              'Średnio ${st.slopePerYear! > 0 ? '+' : ''}${fmtNum(st.slopePerYear)}$u na rok. Przy tym tempie wynik może za rok wyjść ${willHigh ? 'powyżej' : 'poniżej'} normy (${refString(last.low, last.high)}).',
              paramKey: s.key));
          continue;
        }
      }

      // duża zmiana między dwoma ostatnimi wynikami
      if (st.changePct != null && st.changePct!.abs() >= 25 && st.n >= 2) {
        out.add(Insight(InsightKind.info, '${s.name}: wyraźna zmiana',
            '${fmtNum(st.prev)} → ${fmtNum(st.last)}$u (${st.changePct! > 0 ? '+' : ''}${fmtNum(st.changePct, maxDecimals: 0)}%), nadal w normie.',
            paramKey: s.key));
      }
    }
    int rank(Insight i) => i.kind.index;
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  static int _consecutiveOut(List<SeriesPoint> pts, int status) {
    var c = 0;
    for (var i = pts.length - 1; i >= 0; i--) {
      if (pts[i].status == status) {
        c++;
      } else {
        break;
      }
    }
    return c;
  }

  /// Podstawowe parametry, których ostatni wynik jest starszy niż rok.
  static List<ParamSeries> stale(List<ParamSeries> series) {
    const important = {'HGB', 'WBC', 'PLT', 'GLU', 'CHOL', 'LDL', 'TSH', 'CREA', 'ALT', 'VITD', 'HBA1C', 'FERR', 'TG'};
    final now = DateTime.now();
    return series.where((s) => important.contains(s.key) && s.lastDate != null && now.difference(s.lastDate!).inDays > 365).toList();
  }
}

// ---------- pomiary ciała ----------

class BmiInfo {
  final double bmi;
  final String label;
  final int level; // 0 ok, 1 uwaga, 2 źle
  BmiInfo(this.bmi, this.label, this.level);

  static BmiInfo? of(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm < 50) return null;
    final h = heightCm / 100;
    final b = weightKg / (h * h);
    if (b < 18.5) return BmiInfo(b, 'niedowaga', 1);
    if (b < 25) return BmiInfo(b, 'prawidłowa masa ciała', 0);
    if (b < 30) return BmiInfo(b, 'nadwaga', 1);
    return BmiInfo(b, 'otyłość', 2);
  }
}

class BpSummary {
  final double sys, dia;
  final int n;
  final String label;
  final int level;
  BpSummary(this.sys, this.dia, this.n, this.label, this.level);

  /// Średnia z ostatnich [days] dni wg klasyfikacji ESC/ESH.
  static BpSummary? of(List<Measurement> bp, {int days = 30}) {
    final from = DateTime.now().subtract(Duration(days: days));
    final l = bp.where((m) => m.date.isAfter(from) && m.value2 != null).toList();
    if (l.isEmpty) return null;
    final s = l.map((e) => e.value).reduce((a, b) => a + b) / l.length;
    final d = l.map((e) => e.value2!).reduce((a, b) => a + b) / l.length;
    String label;
    int level;
    if (s >= 140 || d >= 90) {
      label = 'nadciśnienie';
      level = 2;
    } else if (s >= 130 || d >= 85) {
      label = 'wysokie prawidłowe';
      level = 1;
    } else if (s >= 120 || d >= 80) {
      label = 'prawidłowe';
      level = 0;
    } else {
      label = 'optymalne';
      level = 0;
    }
    return BpSummary(s, d, l.length, label, level);
  }
}

class MeasureStats {
  final double last, min, max, mean;
  final double? change30, change90;
  MeasureStats(this.last, this.min, this.max, this.mean, this.change30, this.change90);

  static MeasureStats? of(List<Measurement> l) {
    if (l.isEmpty) return null;
    final v = l.map((e) => e.value).toList();
    double? changeSince(int days) {
      final from = l.last.date.subtract(Duration(days: days));
      final older = l.where((m) => !m.date.isAfter(from)).toList();
      if (older.isEmpty) return null;
      return l.last.value - older.last.value;
    }

    return MeasureStats(v.last, v.reduce((a, b) => a < b ? a : b), v.reduce((a, b) => a > b ? a : b), v.reduce((a, b) => a + b) / v.length, changeSince(30), changeSince(90));
  }
}
