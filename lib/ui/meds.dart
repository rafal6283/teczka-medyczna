import 'package:flutter/material.dart';
import 'package:rodzina_wykresy/rodzina_wykresy.dart' show CalendarHeatmap, staggered, AnimatedSplitBar;

import '../data/db.dart';
import '../data/med_notify.dart';
import '../data/meds.dart';
import '../data/models.dart';
import 'common.dart';

class _MedsData {
  final List<Dose> today;
  final List<Med> meds;
  final Map<String, Adherence> adh;
  _MedsData(this.today, this.meds, this.adh);
}

/// Leki: dzisiejsze dawki do odhaczenia, lista leków z godzinami, przestrzeganie z 30 dni.
class MedsTab extends StatelessWidget {
  final Profile profile;
  const MedsTab({super.key, required this.profile});

  Future<_MedsData> _load() async {
    final db = AppDb.I;
    return _MedsData(await db.dosesOn(profile.id!, DateTime.now()), await db.meds(profile.id!), await db.adherence(profile.id!));
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<_MedsData>(
      dep: profile.id,
      load: _load,
      builder: (context, d) {
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final now = DateTime.now();
        final done = d.today.where((x) => x.taken == true).length;
        final sum = d.adh.values.fold<List<int>>([0, 0, 0], (a, x) => [a[0] + x.planned, a[1] + x.taken, a[2] + x.missed]);
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: staggered([
          if (d.meds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.medication_outlined,
                title: 'Dodaj leki',
                text: 'Wpisz lek i godziny dawek – aplikacja przypomni o nich i policzy, jak regularnie je bierzesz. '
                    'Pominięte dawki trafiają też do Polar EKG („Co poprzedza napady”).',
              ),
            ),
          if (d.today.isNotEmpty) ...[
            SectionTitle('Dziś · $done z ${d.today.length}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedSplitBar(parts: [
                (done.toDouble(), StatusColors.ok(context)),
                ((d.today.length - done).toDouble(), cs.surfaceContainerHighest),
              ]),
            ),
            for (final x in d.today)
              CheckboxListTile(
                value: x.taken ?? false,
                tristate: false,
                onChanged: (v) => AppDb.I.markDose(x.med, x.day, x.time, v == true ? true : null),
                title: Text('${x.time} · ${x.med.name}'),
                subtitle: Text([
                  if (x.med.dose.isNotEmpty) x.med.dose,
                  if (x.taken == false) 'pominięta',
                  if (x.taken == null && now.isAfter(x.at.add(const Duration(minutes: 30)))) 'czas minął',
                ].join(' · ')),
                secondary: IconButton(
                  tooltip: 'Pominięta',
                  icon: Icon(Icons.block, color: x.taken == false ? StatusColors.high(context) : cs.outline),
                  onPressed: () => AppDb.I.markDose(x.med, x.day, x.time, x.taken == false ? null : false),
                ),
              ),
          ],
          if (sum[0] > 0) ...[
            const SectionTitle('Ostatnie 30 dni'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Przyjęte ${sum[1]} z ${sum[0]} dawek (${(sum[1] * 100 / sum[0]).round()}%) · pominięte ${sum[2]}',
                  style: t.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: CalendarHeatmap(
                values: {for (final e in d.adh.entries) DateTime.parse('${e.key}T00:00:00'): e.value.pct * 100},
                color: StatusColors.ok(context),
                weeks: 5,
                format: (v) => '${v.round()}% dawek',
              ),
            ),
          ],
          if (d.meds.isNotEmpty) ...[
            SectionTitle('Leki (${d.meds.length})'),
            for (final m in d.meds)
              ListTile(
                leading: Icon(Icons.medication_outlined, color: m.active ? cs.primary : cs.outline),
                title: Text(m.name, style: TextStyle(color: m.active ? null : cs.outline)),
                subtitle: Text([if (m.dose.isNotEmpty) m.dose, m.times.join(', '), if (!m.active) 'odstawiony', if (!m.remind) 'bez przypomnień'].join(' · ')),
                onTap: () => editMed(context, profile, m),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(onPressed: () => editMed(context, profile), icon: const Icon(Icons.add), label: const Text('Dodaj lek')),
          ),
        ]));
      },
    );
  }
}

Future<void> editMed(BuildContext context, Profile p, [Med? m]) async {
  final name = TextEditingController(text: m?.name ?? '');
  final dose = TextEditingController(text: m?.dose ?? '');
  final times = <String>[...(m?.times ?? const ['08:00'])];
  var active = m?.active ?? true, remind = m?.remind ?? true;
  final ok = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return AlertDialog(
        title: Text(m == null ? 'Nowy lek' : 'Lek'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nazwa'), textCapitalization: TextCapitalization.sentences),
            TextField(controller: dose, decoration: const InputDecoration(labelText: 'Dawka (np. 1 tabl., 5 mg)')),
            const SizedBox(height: 12),
            const Text('Godziny dawek'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tm in times)
                InputChip(label: Text(tm), onDeleted: times.length > 1 ? () => set(() => times.remove(tm)) : null),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Godzina'),
                onPressed: () async {
                  final r = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 20, minute: 0));
                  if (r == null) return;
                  final s = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
                  if (!times.contains(s)) set(() => (times..add(s)).sort());
                },
              ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Przypomnienia'), value: remind, onChanged: (v) => set(() => remind = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Biorę obecnie'), value: active, onChanged: (v) => set(() => active = v)),
          ]),
        ),
        actions: [
          if (m != null) TextButton(onPressed: () => Navigator.pop(ctx, 'del'), child: const Text('Usuń')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Zapisz')),
        ],
      );
    }),
  );
  if (ok == 'del' && m?.id != null) {
    await AppDb.I.deleteMed(m!.id!);
  } else if (ok == 'ok' && name.text.trim().isNotEmpty) {
    await AppDb.I.saveMed(Med(
        id: m?.id, profileId: p.id!, name: name.text.trim(), dose: dose.text.trim(), times: times, active: active, remind: remind, notes: m?.notes ?? ''));
    if (remind) await MedNotify.requestPermission();
  } else {
    return;
  }
  await MedNotify.reschedule();
}
