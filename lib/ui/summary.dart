import 'package:flutter/material.dart';

import '../analysis/stats.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../parse/report_parser.dart';
import '../parse/text_utils.dart';
import 'common.dart';
import 'documents.dart';
import 'measurements.dart';
import 'params.dart';
import 'profile_edit.dart';

class _SumData {
  final List<ParamSeries> series;
  final List<MedDocument> docs;
  final List<Measurement> meas;
  _SumData(this.series, this.docs, this.meas);
}

class SummaryTab extends StatelessWidget {
  final Profile profile;
  final ValueChanged<int> goTo;
  const SummaryTab({super.key, required this.profile, required this.goTo});

  Future<_SumData> _load() async {
    final db = AppDb.I;
    return _SumData(await loadSeries(profile), await db.getDocuments(profile.id!), await db.getMeasurements(profile.id!));
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<_SumData>(
      dep: profile.id,
      load: _load,
      builder: (context, d) {
        final insights = Insights.forSeries(d.series);
        final stale = Insights.stale(d.series);
        final measured = d.series.where((s) => s.latest != null).toList();
        final inRange = measured.where((s) => s.latest!.status == 0).length;
        final outRange = measured.where((s) => (s.latest!.status ?? 0) != 0).length;
        final weights = d.meas.where((m) => m.type == MType.weight.key).toList();
        final heights = d.meas.where((m) => m.type == MType.height.key).toList();
        final bmi = BmiInfo.of(weights.isEmpty ? null : weights.last.value, heights.isNotEmpty ? heights.last.value : profile.heightCm);
        final bp = BpSummary.of(d.meas.where((m) => m.type == MType.bp.key).toList());
        final cs = Theme.of(context).colorScheme;
        final lastDoc = d.docs.isEmpty ? null : d.docs.first;

        return ListView(padding: const EdgeInsets.only(bottom: 96, top: 4), children: [
          _profileCard(context, bmi, weights.isEmpty ? null : weights.last),
          if (d.docs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.upload_file,
                title: 'Dodaj pierwszy wynik',
                text: 'Wybierz PDF z laboratorium, zeskanuj papierowy wynik albo wpisz wartości ręcznie. '
                    'Aplikacja rozpozna parametry i zacznie śledzić ich zmiany.',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                _stat(context, '${d.docs.length}', 'dokumentów', () => goTo(1)),
                _stat(context, '${d.series.length}', 'parametrów', () => goTo(2)),
                _stat(context, '$outRange', 'poza normą', () => goTo(2), color: outRange > 0 ? StatusColors.high(context) : null),
              ]),
            ),
            if (measured.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(children: [
                    if (inRange > 0) Expanded(flex: inRange, child: Container(height: 8, color: StatusColors.ok(context))),
                    if (outRange > 0) Expanded(flex: outRange, child: Container(height: 8, color: StatusColors.high(context))),
                    if (measured.length - inRange - outRange > 0)
                      Expanded(flex: measured.length - inRange - outRange, child: Container(height: 8, color: cs.outlineVariant)),
                  ]),
                ),
              ),
            if (measured.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text('Ostatnie wyniki: $inRange w normie, $outRange poza normą'
                    '${lastDoc != null ? ' • ostatnie badanie ${fmtDate(lastDoc.date)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
          if (insights.isNotEmpty) ...[
            SectionTitle('Na co zwrócić uwagę (${insights.length})'),
            for (final i in insights.take(8)) _insight(context, i),
            if (insights.length > 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton(onPressed: () => goTo(2), child: Text('Wszystkie parametry (${insights.length - 8} więcej uwag)')),
              ),
          ] else if (measured.isNotEmpty) ...[
            const SectionTitle('Na co zwrócić uwagę'),
            InfoCard(
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: StatusColors.ok(context)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Wszystkie ostatnie wyniki mieszczą się w normie i nie widać niepokojących trendów.')),
              ]),
            ),
          ],
          ..._followUps(context, d.docs),
          ..._reportNotes(context, d.docs),
          if (bp != null) ...[
            const SectionTitle('Ciśnienie – ostatnie 30 dni'),
            InfoCard(
              onTap: () => goTo(3),
              child: Row(children: [
                Text('${fmtNum(bp.sys, maxDecimals: 0)}/${fmtNum(bp.dia, maxDecimals: 0)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Text('mmHg'),
                const Spacer(),
                Text('${bp.label}\n${bp.n} pomiarów',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: bp.level == 0 ? StatusColors.ok(context) : bp.level == 1 ? StatusColors.warn(context) : StatusColors.high(context))),
              ]),
            ),
          ],
          if (stale.isNotEmpty) ...[
            const SectionTitle('Dawno niebadane'),
            InfoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in stale)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(s.name)),
                      Text('ostatnio ${fmtMonthYear(s.lastDate!)}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
              ]),
            ),
          ],
          if (d.docs.isNotEmpty) ...[
            SectionTitle('Ostatnie dokumenty', trailing: TextButton(onPressed: () => goTo(1), child: const Text('Wszystkie'))),
            for (final doc in d.docs.take(4))
              ListTile(
                leading: Icon(categoryIcon(doc.category)),
                title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${fmtDate(doc.date)}${doc.facility != null ? ' • ${doc.facility}' : ''}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: doc.id!, profile: profile))),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Analiza ma charakter informacyjny i nie zastępuje konsultacji lekarskiej. Normy zależą od laboratorium, wieku i stanu zdrowia.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ),
        ]);
      },
    );
  }

  Widget _profileCard(BuildContext context, BmiInfo? bmi, Measurement? weight) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[
      if (profile.birthDate != null) '${ageOn(profile.birthDate!, DateTime.now())} lat',
      if (profile.sex != null) profile.sex == 'K' ? 'kobieta' : 'mężczyzna',
      if (profile.heightCm != null) '${fmtNum(profile.heightCm)} cm',
      if (weight != null) '${fmtNum(weight.value)} kg',
      if (profile.bloodType != null) 'grupa ${profile.bloodType}',
    ];
    return InfoCard(
      color: Color(profile.color).withValues(alpha: 0.10),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: profile))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(profile.name, style: Theme.of(context).textTheme.titleLarge)),
          if (bmi != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('BMI ${fmtNum(bmi.bmi, maxDecimals: 1)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(bmi.label,
                  style: TextStyle(fontSize: 12, color: bmi.level == 0 ? StatusColors.ok(context) : bmi.level == 1 ? StatusColors.warn(context) : StatusColors.high(context))),
            ]),
        ]),
        if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(chips.join(' • '), style: TextStyle(color: cs.onSurfaceVariant))),
        if (profile.allergies != null) _line(context, Icons.warning_amber_rounded, 'Alergie: ${profile.allergies}', StatusColors.warn(context)),
        if (profile.chronic != null) _line(context, Icons.healing_outlined, profile.chronic!, null),
        if (profile.medications != null) _line(context, Icons.medication_outlined, profile.medications!, null),
        if (chips.isEmpty && profile.allergies == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Uzupełnij datę urodzenia, płeć i wzrost – poprawią ocenę wyników.', style: TextStyle(color: cs.primary)),
          ),
        if (weight == null && profile.heightCm != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => addMeasurement(context, profile, type: MType.weight),
              icon: const Icon(Icons.monitor_weight_outlined, size: 18),
              label: const Text('Dodaj masę ciała, aby policzyć BMI'),
            ),
          ),
      ]),
    );
  }

  /// Zalecone kontrole: zaległe i w ciągu 4 miesięcy (pomijamy, jeśli później wykonano takie samo badanie).
  List<Widget> _followUps(BuildContext context, List<MedDocument> docs) {
    final now = DateTime.now();
    final items = <(MedDocument, DateTime)>[];
    for (final d in docs) {
      final fu = d.followUp;
      if (fu == null) continue;
      final type = DoctorReport.fromJson(d.report)?.examType;
      final redone = docs.any((o) =>
          o.id != d.id &&
          o.date.isAfter(d.date.add(const Duration(days: 30))) &&
          (type != null ? DoctorReport.fromJson(o.report)?.examType == type : o.title == d.title));
      if (redone) continue;
      if (fu.isBefore(now.add(const Duration(days: 120)))) items.add((d, fu));
    }
    if (items.isEmpty) return [];
    items.sort((a, b) => a.$2.compareTo(b.$2));
    return [
      const SectionTitle('Zalecane kontrole'),
      for (final it in items)
        InfoCard(
          padding: const EdgeInsets.all(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: it.$1.id!, profile: profile))),
          child: Row(children: [
            Icon(Icons.event_repeat, color: it.$2.isBefore(now) ? StatusColors.high(context) : StatusColors.warn(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.$1.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Kontrola: ${followUpLabel(it.$2)} • zalecona po badaniu z ${fmtDate(it.$1.date)}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
    ];
  }

  /// Najważniejsze zapisy z ostatniego opisu każdego rodzaju badania.
  List<Widget> _reportNotes(BuildContext context, List<MedDocument> docs) {
    final seen = <String>{};
    final cards = <Widget>[];
    for (final d in docs) {
      final r = DoctorReport.fromJson(d.report);
      if (r == null) continue;
      final k = r.examType ?? d.title;
      if (seen.contains(k)) continue;
      seen.add(k);
      final abn = r.abnormal;
      if (abn.isEmpty && r.conclusions.isEmpty) continue;
      cards.add(InfoCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: d.id!, profile: profile))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(abn.isEmpty ? Icons.check_circle_outline : Icons.priority_high, size: 18, color: abn.isEmpty ? StatusColors.ok(context) : StatusColors.warn(context)),
            const SizedBox(width: 8),
            Expanded(child: Text('${r.examName ?? d.title} • ${fmtDate(d.date)}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          if (r.conclusions.isNotEmpty)
            Text(r.conclusions, maxLines: 3, overflow: TextOverflow.ellipsis)
          else
            for (final f in abn.take(2)) Text('• ${f.sentence}', maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ));
      if (cards.length >= 6) break;
    }
    if (cards.isEmpty) return [];
    return [const SectionTitle('Z opisów badań'), ...cards];
  }

  Widget _line(BuildContext context, IconData i, String t, Color? c) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: c ?? Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(t)),
        ]),
      );

  Widget _stat(BuildContext context, String v, String l, VoidCallback onTap, {Color? color}) => Expanded(
        child: Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text(v, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                Text(l, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ),
      );

  Widget _insight(BuildContext context, Insight i) {
    final (IconData icon, Color c) = switch (i.kind) {
      InsightKind.alert => (Icons.error_outline, StatusColors.high(context)),
      InsightKind.warning => (Icons.warning_amber_rounded, StatusColors.warn(context)),
      InsightKind.good => (Icons.check_circle_outline, StatusColors.ok(context)),
      InsightKind.info => (Icons.info_outline, Theme.of(context).colorScheme.primary),
    };
    return InfoCard(
      padding: const EdgeInsets.all(14),
      onTap: i.paramKey == null
          ? null
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParamDetailScreen(profile: profile, paramKey: i.paramKey!))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(i.text, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
