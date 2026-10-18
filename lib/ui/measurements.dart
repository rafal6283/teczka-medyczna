import 'package:flutter/material.dart';

import '../analysis/stats.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../parse/text_utils.dart';
import 'charts.dart';
import 'common.dart';

int? mStatus(MType t, Measurement m) {
  if (t.key == MType.bp.key) {
    if (m.value >= 140 || (m.value2 ?? 0) >= 90) return 1;
    if (m.value < 90 || (m.value2 ?? 100) < 60) return -1;
    return 0;
  }
  if (t.low == null && t.high == null) return null;
  if (t.low != null && m.value < t.low!) return -1;
  if (t.high != null && m.value > t.high!) return 1;
  return 0;
}

String mValue(MType t, Measurement m) => t.twoValues ? '${fmtNum(m.value)}/${fmtNum(m.value2)}' : fmtNum(m.value);

class MeasurementsTab extends StatelessWidget {
  final Profile profile;
  const MeasurementsTab({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Reloading<List<Measurement>>(
      dep: profile.id,
      load: () => AppDb.I.getMeasurements(profile.id!),
      builder: (context, all) {
        final byType = <String, List<Measurement>>{};
        for (final m in all) {
          byType.putIfAbsent(m.type, () => []).add(m);
        }
        final weights = byType[MType.weight.key] ?? [];
        final heights = byType[MType.height.key] ?? [];
        final h = heights.isNotEmpty ? heights.last.value : profile.heightCm;
        final bmi = BmiInfo.of(weights.isEmpty ? null : weights.last.value, h);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'm',
            onPressed: () => addMeasurement(context, profile),
            icon: const Icon(Icons.add),
            label: const Text('Pomiar'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96, top: 8), children: [
            if (bmi != null)
              InfoCard(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('BMI', style: Theme.of(context).textTheme.labelLarge),
                      Text(fmtNum(bmi.bmi, maxDecimals: 1), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(bmi.label, style: TextStyle(color: bmi.level == 0 ? StatusColors.ok(context) : bmi.level == 1 ? StatusColors.warn(context) : StatusColors.high(context))),
                    ]),
                  ),
                  Text('${fmtNum(weights.last.value)} kg\n${fmtNum(h)} cm', textAlign: TextAlign.right),
                ]),
              ),
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Brak pomiarów',
                  text: 'Zapisuj masę ciała, ciśnienie, tętno, glukozę z glukometru czy temperaturę – zobaczysz wykresy i średnie.',
                ),
              ),
            for (final t in MType.all)
              if ((byType[t.key] ?? []).isNotEmpty) _card(context, t, byType[t.key]!),
          ]),
        );
      },
    );
  }

  Widget _card(BuildContext context, MType t, List<Measurement> l) {
    final last = l.last;
    final st = mStatus(t, last);
    String extra = '';
    if (t.key == MType.bp.key) {
      final s = BpSummary.of(l);
      if (s != null) extra = 'Śr. 30 dni: ${fmtNum(s.sys, maxDecimals: 0)}/${fmtNum(s.dia, maxDecimals: 0)} (${s.label}, ${s.n} pom.)';
    } else {
      final s = MeasureStats.of(l);
      if (s != null && s.change30 != null) extra = 'Zmiana w 30 dni: ${s.change30! >= 0 ? '+' : ''}${fmtNum(s.change30)} ${t.unit}';
    }
    return InfoCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeasureDetailScreen(profile: profile, type: t))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(t.name, style: Theme.of(context).textTheme.titleSmall)),
          Text(fmtDate(last.date), style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(mValue(t, last), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: StatusColors.of(context, st))),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t.unit)),
          const Spacer(),
          if (l.length >= 2) Sparkline(l.map((e) => e.value).toList(), low: t.twoValues ? null : t.low, high: t.twoValues ? null : t.high, color: Theme.of(context).colorScheme.primary),
        ]),
        if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(extra, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

Future<void> addMeasurement(BuildContext context, Profile profile, {MType? type, Measurement? edit}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _MeasureEditor(profile: profile, type: type ?? (edit != null ? MType.byKey(edit.type) : MType.weight), edit: edit),
    ),
  );
}

class _MeasureEditor extends StatefulWidget {
  final Profile profile;
  final MType type;
  final Measurement? edit;
  const _MeasureEditor({required this.profile, required this.type, this.edit});
  @override
  State<_MeasureEditor> createState() => _MeasureEditorState();
}

class _MeasureEditorState extends State<_MeasureEditor> {
  late MType type = widget.type;
  late final v1 = TextEditingController(text: widget.edit == null ? '' : fmtNum(widget.edit!.value));
  late final v2 = TextEditingController(text: widget.edit?.value2 == null ? '' : fmtNum(widget.edit!.value2));
  late final note = TextEditingController(text: widget.edit?.note ?? '');
  late DateTime date = widget.edit?.date ?? DateTime.now();

  Future<void> _save() async {
    final a = parseNum(v1.text);
    final b = parseNum(v2.text);
    if (a == null || (type.twoValues && b == null)) {
      toast(context, 'Podaj wartość');
      return;
    }
    await AppDb.I.saveMeasurement(Measurement(
      id: widget.edit?.id,
      profileId: widget.profile.id!,
      date: date,
      type: type.key,
      value: a,
      value2: type.twoValues ? b : null,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.edit == null ? 'Nowy pomiar' : 'Popraw pomiar', style: Theme.of(context).textTheme.titleMedium),
        gap,
        DropdownButtonFormField<String>(
          initialValue: type.key,
          decoration: const InputDecoration(labelText: 'Rodzaj'),
          items: [for (final t in MType.all) DropdownMenuItem(value: t.key, child: Text(t.name))],
          onChanged: widget.edit != null ? null : (v) => setState(() => type = MType.byKey(v!)),
        ),
        gap,
        Row(children: [
          Expanded(
            child: TextField(
              controller: v1,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: type.twoValues ? 'Skurczowe' : 'Wartość', suffixText: type.unit),
            ),
          ),
          if (type.twoValues) ...[
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: v2,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Rozkurczowe', suffixText: type.unit),
              ),
            ),
          ],
        ]),
        gap,
        Row(children: [
          Expanded(child: DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute)))),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
                if (t != null) setState(() => date = DateTime(date.year, date.month, date.day, t.hour, t.minute));
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Godzina', suffixIcon: Icon(Icons.schedule, size: 20)),
                child: Text('${two(date.hour)}:${two(date.minute)}'),
              ),
            ),
          ),
        ]),
        gap,
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Notatka (opcjonalnie)')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ]),
    );
  }
}

class MeasureDetailScreen extends StatelessWidget {
  final Profile profile;
  final MType type;
  const MeasureDetailScreen({super.key, required this.profile, required this.type});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type.name)),
      floatingActionButton: FloatingActionButton(onPressed: () => addMeasurement(context, profile, type: type), child: const Icon(Icons.add)),
      body: Reloading<List<Measurement>>(
        load: () => AppDb.I.getMeasurements(profile.id!, type: type.key),
        builder: (context, l) {
          if (l.isEmpty) return const Center(child: Text('Brak pomiarów'));
          final s = MeasureStats.of(l)!;
          final bp = type.twoValues ? BpSummary.of(l) : null;
          final rows = <(String, String)>[
            ('Liczba pomiarów', '${l.length}'),
            if (!type.twoValues) ('Min / maks', '${fmtNum(s.min)} / ${fmtNum(s.max)} ${type.unit}'),
            if (!type.twoValues) ('Średnia', '${fmtNum(s.mean)} ${type.unit}'),
            if (s.change30 != null && !type.twoValues) ('Zmiana w 30 dni', '${s.change30! >= 0 ? '+' : ''}${fmtNum(s.change30)} ${type.unit}'),
            if (s.change90 != null && !type.twoValues) ('Zmiana w 90 dni', '${s.change90! >= 0 ? '+' : ''}${fmtNum(s.change90)} ${type.unit}'),
            if (bp != null) ('Średnia z 30 dni', '${fmtNum(bp.sys, maxDecimals: 0)}/${fmtNum(bp.dia, maxDecimals: 0)} mmHg'),
            if (bp != null) ('Ocena (ESC)', bp.label),
          ];
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            if (l.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 12, 0),
                child: TimeChart(
                  points: l.map((m) => ChartPoint(m.date, m.value, y2: m.value2, status: mStatus(type, m))).toList(),
                  low: type.twoValues ? null : type.low,
                  high: type.twoValues ? null : type.high,
                  unit: type.unit,
                  showTrend: !type.twoValues,
                ),
              ),
            InfoCard(
              child: Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(r.$1, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
            const SectionTitle('Historia'),
            for (final m in l.reversed)
              ListTile(
                dense: true,
                leading: StatusDot(mStatus(type, m)),
                minLeadingWidth: 12,
                title: Text('${mValue(type, m)} ${type.unit}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${fmtDate(m.date)} ${two(m.date.hour)}:${two(m.date.minute)}${m.note == null ? '' : ' • ${m.note}'}'),
                onTap: () => addMeasurement(context, profile, edit: m),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (await confirm(context, 'Usunąć pomiar?', '${mValue(type, m)} ${type.unit}, ${fmtDate(m.date)}')) await AppDb.I.deleteMeasurement(m.id!);
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
