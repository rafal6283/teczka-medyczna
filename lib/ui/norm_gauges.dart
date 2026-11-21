import 'dart:math';

import 'package:flutter/material.dart';

import '../analysis/stats.dart';
import '../data/models.dart';
import '../parse/text_utils.dart';
import 'common.dart';
import 'params.dart';

/// Wyniki na tle normy: pasek z zakresem normy (zielony), kropka – ostatni wynik, pusty krążek – poprzedni.
/// Kropka „przejeżdża” od poprzedniego wyniku do ostatniego, więc od razu widać kierunek zmiany.
/// Dotknięcie wiersza otwiera parametr.
class NormGauges extends StatelessWidget {
  final Profile profile;
  final List<ParamSeries> series;
  final int max;
  const NormGauges({super.key, required this.profile, required this.series, this.max = 8});

  static bool usable(ParamSeries s) => s.latest != null && (s.latest!.low != null || s.latest!.high != null);

  @override
  Widget build(BuildContext context) {
    final list = series.where(usable).toList()
      ..sort((a, b) {
        // najpierw poza normą, potem najświeższe
        final oa = (a.latest!.status ?? 0) != 0 ? 0 : 1;
        final ob = (b.latest!.status ?? 0) != 0 ? 0 : 1;
        if (oa != ob) return oa - ob;
        return b.latest!.date.compareTo(a.latest!.date);
      });
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (var i = 0; i < min(max, list.length); i++) _row(context, list[i], i),
    ]);
  }

  Widget _row(BuildContext context, ParamSeries s, int i) {
    final p = s.latest!;
    final prev = s.points.length >= 2 ? s.points[s.points.length - 2] : null;
    final cs = Theme.of(context).colorScheme;
    final st = p.status ?? 0;
    final color = st == 0 ? StatusColors.ok(context) : StatusColors.high(context);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParamDetailScreen(profile: profile, paramKey: s.key))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          SizedBox(
            width: 112,
            child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 900 + 70 * i),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                final k = ((t * (900 + 70 * i) - 70 * i) / 900).clamp(0.0, 1.0);
                final from = prev?.value ?? p.value;
                return CustomPaint(
                  size: const Size(double.infinity, 22),
                  painter: _GaugePainter(
                    low: p.low,
                    high: p.high,
                    value: from + (p.value - from) * Curves.easeInOutCubic.transform(k),
                    prev: prev?.value,
                    appear: k,
                    ok: StatusColors.ok(context),
                    dot: color,
                    track: cs.surfaceContainerHighest,
                    ghost: cs.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              '${fmtNum(p.value)} ${s.unit}'.trim(),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: st == 0 ? null : color, fontSize: 12.5),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double? low, high, prev;
  final double value, appear;
  final Color ok, dot, track, ghost;
  _GaugePainter({
    required this.low,
    required this.high,
    required this.value,
    required this.prev,
    required this.appear,
    required this.ok,
    required this.dot,
    required this.track,
    required this.ghost,
  });

  @override
  void paint(Canvas c, Size size) {
    // zakres osi: norma ± połowa jej szerokości (gdy jest tylko jedna granica – od niej w obie strony)
    final double lo, hi;
    if (low != null && high != null && high! > low!) {
      final span = high! - low!;
      lo = low! - span * 0.5;
      hi = high! + span * 0.5;
    } else if (high != null) {
      lo = 0;
      hi = high! * 1.6;
    } else {
      lo = low! * 0.4;
      hi = low! * 1.8;
    }
    double x(double v) => (((v - lo) / (hi - lo)).clamp(0.0, 1.0)) * size.width;
    final cy = size.height / 2;
    const h = 6.0;
    const r = Radius.circular(3);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, size.width, h), r), Paint()..color = track);
    final a = x(low ?? lo), b = x(high ?? hi);
    // strefa normy rozwija się od środka
    final mid = (a + b) / 2;
    final half = (b - a) / 2 * appear;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(mid - half, cy - h / 2, mid + half, cy + h / 2), r),
        Paint()..color = ok.withValues(alpha: 0.45));
    if (prev != null && appear > 0.2) {
      c.drawCircle(Offset(x(prev!), cy), 4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = ghost.withValues(alpha: 0.7 * appear));
    }
    final vx = x(value);
    c.drawCircle(Offset(vx, cy), 6.5 * (0.6 + 0.4 * appear), Paint()..color = dot);
    c.drawCircle(Offset(vx, cy), 6.5 * (0.6 + 0.4 * appear), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.value != value || o.appear != appear || o.dot != dot;
}
