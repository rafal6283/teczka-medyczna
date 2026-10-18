import 'package:flutter/material.dart';

import '../analysis/stats.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../parse/lab_dictionary.dart';
import '../parse/lab_parser.dart';
import '../parse/text_utils.dart';
import 'charts.dart';
import 'common.dart';
import 'documents.dart';
import 'review.dart';

Future<List<ParamSeries>> loadSeries(Profile p) async => Analysis.build(await AppDb.I.getResults(p.id!), sex: p.sex);

class ParamsTab extends StatefulWidget {
  final Profile profile;
  const ParamsTab({super.key, required this.profile});
  @override
  State<ParamsTab> createState() => _ParamsTabState();
}

class _ParamsTabState extends State<ParamsTab> {
  bool onlyOut = false;
  String q = '';

  @override
  Widget build(BuildContext context) {
    return Reloading<List<ParamSeries>>(
      dep: widget.profile.id,
      load: () => loadSeries(widget.profile),
      builder: (context, all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.insights,
            title: 'Brak wyników do analizy',
            text: 'Po dodaniu dokumentów z wynikami zobaczysz tu wszystkie parametry, ich zmiany w czasie i statystyki.',
            action: OutlinedButton.icon(
              onPressed: () => _addManual(context),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj wynik ręcznie'),
            ),
          );
        }
        final nq = normText(q);
        final list = all.where((s) {
          if (onlyOut && (s.latest?.status ?? 0) == 0) return false;
          if (nq.isNotEmpty && !normText(s.name).contains(nq)) return false;
          return true;
        }).toList();
        final outCount = all.where((s) => (s.latest?.status ?? 0) != 0).length;
        final items = <Widget>[];
        String? lastCat;
        for (final s in list) {
          if (s.category != lastCat) {
            items.add(SectionTitle(s.category));
            lastCat = s.category;
          }
          items.add(_tile(context, s));
        }
        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Szukaj parametru'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              FilterChip(
                label: Text('Poza normą ($outCount)'),
                selected: onlyOut,
                onSelected: (v) => setState(() => onlyOut = v),
              ),
              const Spacer(),
              TextButton.icon(onPressed: () => _addManual(context), icon: const Icon(Icons.add, size: 18), label: const Text('Wynik')),
            ]),
          ),
          if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Brak pasujących parametrów'))),
          ...items,
        ]);
      },
    );
  }

  Future<void> _addManual(BuildContext context, {String? key}) async {
    final r = await showResultEditor(context, sex: widget.profile.sex, fixedKey: key);
    if (r == null || !context.mounted) return;
    final d = await pickDate(context, DateTime.now());
    if (d == null) return;
    await AppDb.I.saveResult(LabResult(
      profileId: widget.profile.id!,
      date: d,
      key: r.key,
      name: r.name,
      value: r.value,
      valueText: r.valueText,
      unit: r.unit,
      refLow: r.refLow,
      refHigh: r.refHigh,
    ));
  }

  Widget _tile(BuildContext context, ParamSeries s) {
    final last = s.latest;
    final st = s.stats;
    final status = last?.status;
    final c = StatusColors.of(context, status);
    return ListTile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParamDetailScreen(profile: widget.profile, paramKey: s.key))),
      leading: StatusDot(status),
      minLeadingWidth: 12,
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        last == null
            ? '${s.textResults.length} wyn. opisowe'
            : '${fmtDate(last.date)} • ${st!.n} ${st.n == 1 ? 'wynik' : 'wyn.'}${st.changePct != null ? ' • ${st.changePct! >= 0 ? '+' : ''}${fmtNum(st.changePct, maxDecimals: 0)}%' : ''}',
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (s.points.length >= 2) Sparkline(s.points.map((e) => e.value).toList(), low: last?.low, high: last?.high, color: c),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(last == null ? (s.textResults.isEmpty ? '–' : (s.textResults.last.valueText ?? '–')) : fmtValue(last.value, last.src.valueText),
                style: TextStyle(fontWeight: FontWeight.w700, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(s.unit, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class ParamDetailScreen extends StatefulWidget {
  final Profile profile;
  final String paramKey;
  const ParamDetailScreen({super.key, required this.profile, required this.paramKey});
  @override
  State<ParamDetailScreen> createState() => _ParamDetailScreenState();
}

class _ParamDetailScreenState extends State<ParamDetailScreen> {
  int range = 0; // 0 wszystko, 1 – 5 lat, 2 – 2 lata, 3 – rok

  Future<ParamSeries?> _load() async {
    final r = await AppDb.I.getResults(widget.profile.id!, key: widget.paramKey);
    if (r.isEmpty) return null;
    final s = Analysis.build(r, sex: widget.profile.sex);
    return s.isEmpty ? null : s.first;
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<ParamSeries?>(
      load: _load,
      builder: (context, s) {
        if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Brak wyników')));
        final p = LabDictionary.get(s.key);
        final now = DateTime.now();
        final cut = [null, now.subtract(const Duration(days: 365 * 5)), now.subtract(const Duration(days: 730)), now.subtract(const Duration(days: 365))][range];
        final pts = s.points.where((e) => cut == null || e.date.isAfter(cut)).toList();
        final filtered = ParamSeries(s.key, s.name, s.category, s.unit, s.known, pts, s.textResults, s.skipped);
        final st = filtered.stats;
        final last = s.latest;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.name),
            actions: [
              if (!s.known)
                IconButton(
                  tooltip: 'Połącz z parametrem ze słownika',
                  icon: const Icon(Icons.merge_type),
                  onPressed: () => _merge(context, s),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Dodaj wynik',
            onPressed: () => _add(context, s),
            child: const Icon(Icons.add),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            if (last != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtValue(last.value, last.src.valueText),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: StatusColors.of(context, last.status))),
                  const SizedBox(width: 6),
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s.unit)),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    StatusChip(last.status),
                    const SizedBox(height: 4),
                    Text(fmtDate(last.date), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ]),
              ),
            if (last != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Text('Norma: ${s.refText} ${s.unit}${last.src.refLow == null && last.src.refHigh == null && (last.low != null || last.high != null) ? ' (orientacyjna)' : ''}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            if (s.points.length >= 2) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Wszystko')),
                    ButtonSegment(value: 1, label: Text('5 lat')),
                    ButtonSegment(value: 2, label: Text('2 lata')),
                    ButtonSegment(value: 3, label: Text('Rok')),
                  ],
                  selected: {range},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => range = v.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 12, 0),
                child: pts.isEmpty
                    ? const SizedBox(height: 120, child: Center(child: Text('Brak wyników w tym okresie')))
                    : TimeChart(
                        points: pts.map((e) => ChartPoint(e.date, e.value, status: e.status)).toList(),
                        low: last?.low,
                        high: last?.high,
                        unit: s.unit,
                      ),
              ),
            ],
            if (st != null && st.n >= 2) _statsCard(context, st, s.unit),
            if (p != null && (s.skipped.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('${s.skipped.length} wynik(ów) w jednostce, której nie umiem przeliczyć na ${s.unit} – nie są na wykresie.',
                    style: TextStyle(color: StatusColors.warn(context), fontSize: 12)),
              ),
            const SectionTitle('Historia wyników'),
            for (final r in [...s.points.map((e) => e.src), ...s.textResults, ...s.skipped]..sort((a, b) => b.date.compareTo(a.date)))
              _historyTile(context, s, r),
            if (p != null) ...[
              const SectionTitle('O parametrze'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Kategoria: ${p.category}. Wartości z różnych laboratoriów są przeliczane na ${p.unit.isEmpty ? 'wspólną skalę' : p.unit}, '
                  'gdy jednostki się różnią. Norma pochodzi z wyniku; jeśli wynik jej nie podaje, użyta jest orientacyjna norma dla dorosłych.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _statsCard(BuildContext context, ParamStats st, String unit) {
    String sgn(double? v, {int dec = 2}) => v == null ? '–' : '${v >= 0 ? '+' : ''}${fmtNum(v, maxDecimals: dec)}';
    final rows = <(String, String)>[
      ('Liczba wyników', '${st.n} (z ${(st.spanDays / 365.25).toStringAsFixed(1).replaceAll('.', ',')} lat)'),
      ('Min / maks', '${fmtNum(st.min)} / ${fmtNum(st.max)}'),
      ('Średnia', fmtNum(st.mean)),
      ('Zmiana od poprzedniego', '${sgn(st.changeAbs)} (${sgn(st.changePct, dec: 0)}%)'),
      ('Zmiana od pierwszego', '${sgn(st.totalPct, dec: 0)}%'),
      if (st.slopePerYear != null) ('Trend roczny', '${sgn(st.slopePerYear)} $unit/rok (${sgn(st.slopePctPerYear, dec: 0)}%)'),
      ('Poza normą', '${st.outCount} z ${st.n}'),
    ];
    return InfoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Statystyki', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          TrendIcon(st.trend),
          const SizedBox(width: 4),
          Text(st.trend > 0 ? 'rośnie' : st.trend < 0 ? 'spada' : 'stabilnie'),
        ]),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  Widget _historyTile(BuildContext context, ParamSeries s, LabResult r) {
    final p = LabDictionary.get(r.key);
    final hasOwn = r.refLow != null || r.refHigh != null;
    final lo = hasOwn ? r.refLow : p?.lowFor(widget.profile.sex);
    final hi = hasOwn ? r.refHigh : p?.highFor(widget.profile.sex);
    final st = statusOf(r.value, lo, hi, r.flag);
    return ListTile(
      dense: true,
      leading: StatusDot(st),
      minLeadingWidth: 12,
      title: Text(fmtDate(r.date)),
      subtitle: Text('norma ${refText(lo, hi)}${r.documentId == null ? ' • wpis ręczny' : ''}'),
      trailing: Text('${fmtValue(r.value, r.valueText)} ${r.unit}', style: TextStyle(fontWeight: FontWeight.w700, color: StatusColors.of(context, st))),
      onTap: () => _resultActions(context, r),
    );
  }

  Future<void> _resultActions(BuildContext context, LabResult r) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r.documentId != null) ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Otwórz dokument'), onTap: () => Navigator.pop(c, 'doc')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Popraw wynik'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Usuń wynik'), onTap: () => Navigator.pop(c, 'del')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (a == 'doc') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: r.documentId!, profile: widget.profile)));
    } else if (a == 'del') {
      if (await confirm(context, 'Usunąć wynik?', '${r.name}: ${fmtValue(r.value, r.valueText)} ${r.unit} z ${fmtDate(r.date)}')) {
        await AppDb.I.deleteResult(r.id!);
      }
    } else if (a == 'edit') {
      final out = await showResultEditor(
        context,
        sex: widget.profile.sex,
        fixedKey: r.key,
        initial: ParsedResultX.fromLab(r),
      );
      if (out == null) return;
      await AppDb.I.saveResult(LabResult(
        id: r.id,
        profileId: r.profileId,
        documentId: r.documentId,
        date: r.date,
        key: r.key,
        name: r.name,
        value: out.value,
        valueText: out.valueText,
        unit: out.unit,
        refLow: out.refLow,
        refHigh: out.refHigh,
        flag: r.flag,
      ));
    }
  }

  Future<void> _add(BuildContext context, ParamSeries s) async {
    final out = await showResultEditor(context, sex: widget.profile.sex, fixedKey: s.key, initial: ParsedResult(key: s.key, name: s.name, unit: s.unit, known: s.known));
    if (out == null || !context.mounted) return;
    final d = await pickDate(context, DateTime.now());
    if (d == null) return;
    await AppDb.I.saveResult(LabResult(
      profileId: widget.profile.id!,
      date: d,
      key: s.key,
      name: s.name,
      value: out.value,
      valueText: out.valueText,
      unit: out.unit.isEmpty ? s.unit : out.unit,
      refLow: out.refLow,
      refHigh: out.refHigh,
    ));
  }

  Future<void> _merge(BuildContext context, ParamSeries s) async {
    final p = await showSearch<LabParam?>(context: context, delegate: ParamSearch());
    if (p == null || !context.mounted) return;
    if (!await confirm(context, 'Połączyć?', '„${s.name}” zostanie zapisany jako „${p.name}” we wszystkich wynikach.', ok: 'Połącz', destructive: false)) return;
    await AppDb.I.renameParam(widget.profile.id!, s.key, p.key, p.name);
    if (context.mounted) Navigator.pop(context);
  }
}
