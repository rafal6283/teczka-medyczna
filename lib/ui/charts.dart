import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parse/text_utils.dart';
import 'common.dart';

class ChartPoint {
  final DateTime date;
  final double y;
  final double? y2; // druga linia (np. ciśnienie rozkurczowe)
  final int? status;
  ChartPoint(this.date, this.y, {this.y2, this.status});
}

/// Wykres w czasie z pasmem normy, kolorowymi punktami i dotykiem.
class TimeChart extends StatefulWidget {
  final List<ChartPoint> points;
  final double? low, high; // pasmo normy
  final String unit;
  final double height;
  final ValueChanged<int>? onSelect;
  final bool showTrend;
  const TimeChart({super.key, required this.points, this.low, this.high, this.unit = '', this.height = 240, this.onSelect, this.showTrend = true});

  @override
  State<TimeChart> createState() => _TimeChartState();
}

class _TimeChartState extends State<TimeChart> with SingleTickerProviderStateMixin {
  int? selected;
  // wykres „rysuje się” od lewej przy pokazaniu i po zmianie danych
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))..forward();

  @override
  void didUpdateWidget(covariant TimeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected != null && selected! >= widget.points.length) selected = null;
    if (!identical(oldWidget.points, widget.points) && oldWidget.points.length != widget.points.length) _reveal.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final painter = _ChartPainter(
        points: widget.points,
        low: widget.low,
        high: widget.high,
        selected: selected,
        line: cs.primary,
        line2: cs.tertiary,
        band: StatusColors.ok(context).withValues(alpha: 0.10),
        grid: cs.outlineVariant.withValues(alpha: 0.6),
        text: cs.onSurfaceVariant,
        okC: StatusColors.ok(context),
        hiC: StatusColors.high(context),
        loC: StatusColors.low(context),
        noneC: cs.primary,
        surface: cs.surface,
        showTrend: widget.showTrend,
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _hit(painter, d.localPosition, Size(c.maxWidth, widget.height)),
        onHorizontalDragUpdate: (d) => _hit(painter, d.localPosition, Size(c.maxWidth, widget.height)),
        child: SizedBox(
          height: widget.height,
          width: c.maxWidth,
          child: Stack(children: [
            AnimatedBuilder(
              animation: _reveal,
              builder: (context, child) => ClipRect(clipper: _RevealClipper(Curves.easeOutCubic.transform(_reveal.value)), child: child),
              child: CustomPaint(size: Size(c.maxWidth, widget.height), painter: painter),
            ),
            if (selected != null && selected! < widget.points.length) _tooltip(context, painter, Size(c.maxWidth, widget.height)),
          ]),
        ),
      );
    });
  }

  void _hit(_ChartPainter p, Offset pos, Size size) {
    if (widget.points.isEmpty) return;
    final layout = p.layout(size);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < widget.points.length; i++) {
      final dx = (layout.x(widget.points[i].date) - pos.dx).abs();
      if (dx < bestD) {
        bestD = dx;
        best = i;
      }
    }
    if (best != selected) {
      HapticFeedback.selectionClick();
      setState(() => selected = best);
      widget.onSelect?.call(best);
    }
  }

  Widget _tooltip(BuildContext context, _ChartPainter p, Size size) {
    final l = p.layout(size);
    final pt = widget.points[selected!];
    final x = l.x(pt.date);
    final y = l.y(pt.y);
    final txt = pt.y2 != null ? '${fmtNum(pt.y)}/${fmtNum(pt.y2)} ${widget.unit}' : '${fmtNum(pt.y)} ${widget.unit}';
    const w = 130.0;
    final left = (x - w / 2).clamp(0.0, size.width - w);
    final top = y < 60 ? y + 14 : y - 52;
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(txt.trim(), style: TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(fmtDate(pt.date), style: TextStyle(color: cs.onInverseSurface.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  final double t;
  _RevealClipper(this.t);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * (0.04 + 0.96 * t), size.height);
  @override
  bool shouldReclip(covariant _RevealClipper old) => old.t != t;
}

class _Layout {
  final Rect area;
  final DateTime t0, t1;
  final double y0, y1;
  _Layout(this.area, this.t0, this.t1, this.y0, this.y1);
  double x(DateTime d) {
    final span = t1.difference(t0).inMilliseconds;
    if (span <= 0) return area.center.dx;
    return area.left + (d.difference(t0).inMilliseconds / span) * area.width;
  }

  double y(double v) => area.bottom - (v - y0) / (y1 - y0) * area.height;
}

class _ChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final double? low, high;
  final int? selected;
  final Color line, line2, band, grid, text, okC, hiC, loC, noneC, surface;
  final bool showTrend;

  _ChartPainter({
    required this.points,
    this.low,
    this.high,
    this.selected,
    required this.line,
    required this.line2,
    required this.band,
    required this.grid,
    required this.text,
    required this.okC,
    required this.hiC,
    required this.loC,
    required this.noneC,
    required this.surface,
    required this.showTrend,
  });

  _Layout layout(Size size) {
    final vals = <double>[];
    for (final p in points) {
      vals.add(p.y);
      if (p.y2 != null) vals.add(p.y2!);
    }
    if (low != null) vals.add(low!);
    if (high != null) vals.add(high!);
    var mn = vals.isEmpty ? 0.0 : vals.reduce(min);
    var mx = vals.isEmpty ? 1.0 : vals.reduce(max);
    if ((mx - mn).abs() < 1e-9) {
      mn -= mn.abs() * 0.1 + 1;
      mx += mx.abs() * 0.1 + 1;
    }
    final pad = (mx - mn) * 0.12;
    mn -= pad;
    mx += pad;
    if (mn < 0 && vals.every((v) => v >= 0)) mn = 0;
    final (n0, n1, _) = _nice(mn, mx);
    var t0 = points.isEmpty ? DateTime.now() : points.first.date;
    var t1 = points.isEmpty ? DateTime.now() : points.last.date;
    if (t1.difference(t0).inDays < 1) {
      t0 = t0.subtract(const Duration(days: 15));
      t1 = t1.add(const Duration(days: 15));
    } else {
      final m = t1.difference(t0) * 0.04;
      t0 = t0.subtract(m);
      t1 = t1.add(m);
    }
    final area = Rect.fromLTRB(44, 12, size.width - 10, size.height - 26);
    return _Layout(area, t0, t1, n0, n1);
  }

  static (double, double, double) _nice(double mn, double mx) {
    final range = mx - mn;
    final rough = range / 4;
    final mag = pow(10, (log(rough) / ln10).floor()).toDouble();
    final norm = rough / mag;
    final step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    return ((mn / step).floor() * step, (mx / step).ceil() * step, step);
  }

  Color _c(int? s) {
    if (s == null) return noneC;
    if (s > 0) return hiC;
    if (s < 0) return loC;
    return okC;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout(size);
    final a = l.area;
    final ts = TextStyle(color: text, fontSize: 10.5);

    // pasmo normy
    if (low != null || high != null) {
      final top = high != null ? l.y(high!).clamp(a.top, a.bottom) : a.top;
      final bot = low != null ? l.y(low!).clamp(a.top, a.bottom) : a.bottom;
      canvas.drawRect(Rect.fromLTRB(a.left, top, a.right, bot), Paint()..color = band);
      final dash = Paint()
        ..color = okC.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (final v in [low, high]) {
        if (v == null) continue;
        final y = l.y(v);
        if (y < a.top || y > a.bottom) continue;
        for (var x = a.left; x < a.right; x += 8) {
          canvas.drawLine(Offset(x, y), Offset(min(x + 4, a.right), y), dash);
        }
      }
    }

    // siatka Y
    final (_, _, step) = _nice(l.y0, l.y1);
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 0.7;
    for (var v = l.y0; v <= l.y1 + step * 0.01; v += step) {
      final y = l.y(v);
      canvas.drawLine(Offset(a.left, y), Offset(a.right, y), gp);
      _text(canvas, fmtNum(v), Offset(a.left - 6, y), ts, alignRight: true);
    }

    // etykiety X
    if (points.isNotEmpty) {
      final span = l.t1.difference(l.t0).inDays;
      final labels = <DateTime>[];
      if (span <= 120) {
        for (final p in points) {
          labels.add(p.date);
        }
      } else {
        var d = DateTime(l.t0.year, l.t0.month + 1);
        final stepM = span > 365 * 4 ? 12 : span > 365 * 2 ? 6 : span > 365 ? 3 : 1;
        while (d.isBefore(l.t1)) {
          labels.add(d);
          d = DateTime(d.year, d.month + stepM);
        }
      }
      double lastX = -100;
      for (final d in labels) {
        final x = l.x(d);
        if (x - lastX < 46 || x < a.left || x > a.right) continue;
        lastX = x;
        _text(canvas, span <= 120 ? '${two(d.day)}.${two(d.month)}' : fmtDateShort(d), Offset(x, a.bottom + 13), ts, center: true);
      }
    }

    if (points.isEmpty) return;

    // linia trendu
    if (showTrend && points.length >= 3) {
      final t0 = points.first.date.millisecondsSinceEpoch.toDouble();
      final xs = points.map((p) => p.date.millisecondsSinceEpoch - t0).toList();
      final ys = points.map((p) => p.y).toList();
      final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
      var sxy = 0.0, sxx = 0.0;
      for (var i = 0; i < xs.length; i++) {
        sxy += (xs[i] - mx) * (ys[i] - my);
        sxx += (xs[i] - mx) * (xs[i] - mx);
      }
      if (sxx > 0) {
        final k = sxy / sxx;
        final p1 = Offset(l.x(points.first.date), l.y(my + k * (xs.first - mx)));
        final p2 = Offset(l.x(points.last.date), l.y(my + k * (xs.last - mx)));
        final tp = Paint()
          ..color = text.withValues(alpha: 0.45)
          ..strokeWidth = 1.2;
        final dist = (p2 - p1).distance;
        for (var s = 0.0; s < dist; s += 9) {
          final e = min(s + 5, dist);
          canvas.drawLine(Offset.lerp(p1, p2, s / dist)!, Offset.lerp(p1, p2, e / dist)!, tp);
        }
      }
    }

    void drawSeries(List<Offset> pts, Color c) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round);
    }

    final p1 = points.map((p) => Offset(l.x(p.date), l.y(p.y))).toList();
    drawSeries(p1, line);
    final has2 = points.any((p) => p.y2 != null);
    if (has2) {
      drawSeries(points.where((p) => p.y2 != null).map((p) => Offset(l.x(p.date), l.y(p.y2!))).toList(), line2);
    }

    final dense = points.length > 60;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = p1[i];
      final r = i == selected ? 6.5 : (dense ? 2.5 : 4.5);
      canvas.drawCircle(o, r + 1.5, Paint()..color = surface);
      canvas.drawCircle(o, r, Paint()..color = _c(p.status));
      if (p.y2 != null) {
        final o2 = Offset(o.dx, l.y(p.y2!));
        canvas.drawCircle(o2, r + 1.5, Paint()..color = surface);
        canvas.drawCircle(o2, r, Paint()..color = line2);
      }
    }
    if (selected != null && selected! < points.length) {
      final x = p1[selected!].dx;
      canvas.drawLine(Offset(x, a.top), Offset(x, a.bottom), Paint()
        ..color = text.withValues(alpha: 0.4)
        ..strokeWidth = 1);
    }
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle st, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}

/// Mały wykres do list.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double? low, high;
  final Color color;
  const Sparkline(this.values, {super.key, this.low, this.high, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(64, 26),
        painter: _SparkPainter(values, low, high, color, StatusColors.ok(context).withValues(alpha: 0.13)),
      );
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final double? low, high;
  final Color color, band;
  _SparkPainter(this.v, this.low, this.high, this.color, this.band);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final all = [...v];
    var mn = all.reduce(min), mx = all.reduce(max);
    if (low != null) mn = min(mn, low!);
    if (high != null) mx = max(mx, high!);
    if ((mx - mn).abs() < 1e-9) {
      mn -= 1;
      mx += 1;
    }
    double y(double x) => size.height - 2 - (x - mn) / (mx - mn) * (size.height - 4);
    if (low != null || high != null) {
      canvas.drawRect(Rect.fromLTRB(0, high != null ? y(high!) : 0, size.width, low != null ? y(low!) : size.height), Paint()..color = band);
    }
    final dx = v.length == 1 ? 0.0 : size.width / (v.length - 1);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final o = Offset(v.length == 1 ? size.width / 2 : i * dx, y(v[i]));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
    canvas.drawCircle(Offset(v.length == 1 ? size.width / 2 : (v.length - 1) * dx, y(v.last)), 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter o) => true;
}
