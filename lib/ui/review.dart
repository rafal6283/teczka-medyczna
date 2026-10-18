import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../parse/figures.dart';
import '../parse/lab_dictionary.dart';
import '../parse/lab_parser.dart';
import '../parse/report_parser.dart';
import '../parse/text_utils.dart';
import 'common.dart';
import 'documents.dart';
import 'import_flow.dart';
import 'viewer.dart';

int? statusOf(double? v, double? lo, double? hi, String? flag) {
  if (v != null && (lo != null || hi != null)) {
    if (lo != null && v < lo - 1e-9) return -1;
    if (hi != null && v > hi + 1e-9) return 1;
    return 0;
  }
  if (flag == 'H') return 1;
  if (flag == 'L') return -1;
  return null;
}

/// Weryfikacja rozpoznanych danych przed zapisem.
class ReviewScreen extends StatefulWidget {
  final Profile profile;
  final List<PickedFile> files;
  final ParseOutput parsed;
  final String text;
  final bool usedOcr;
  final List<FigureCrop> figures;
  final MedDocument? existing;
  final DoctorReport? report;
  const ReviewScreen({
    super.key,
    required this.profile,
    required this.files,
    required this.parsed,
    required this.text,
    required this.usedOcr,
    required this.figures,
    this.existing,
    this.report,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final title = TextEditingController(text: widget.existing?.title ?? widget.parsed.suggestedTitle);
  late final facility = TextEditingController(text: widget.existing?.facility ?? widget.parsed.facility ?? '');
  late final doctor = TextEditingController(text: widget.existing?.doctor ?? '');
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');
  late DateTime date = widget.existing?.date ?? widget.parsed.date ?? DateTime.now();
  late String category = widget.existing?.category ?? widget.parsed.suggestedCategory;
  late final List<ParsedResult> results = List.of(widget.parsed.results);
  late final List<bool> figSel = List.filled(widget.figures.length, true);
  bool saving = false;
  late final DoctorReport? _rep = widget.report ?? DoctorReport.fromJson(widget.existing?.report);
  late final conc = TextEditingController(text: _rep?.conclusions ?? '');
  late final desc = TextEditingController(text: _rep?.description ?? '');
  late final recs = TextEditingController(text: _rep?.recommendations ?? '');
  late DateTime? followUp = _rep?.followUp ?? widget.existing?.followUp;
  late bool showReport = _rep != null && (_rep?.isEmpty == false || _rep?.examType != null || category != DocCategories.lab);

  DoctorReport? _buildReport() {
    if (conc.text.trim().isEmpty && desc.text.trim().isEmpty && recs.text.trim().isEmpty) return null;
    final r = DoctorReport(
      examType: _rep?.examType,
      description: desc.text.trim(),
      conclusions: conc.text.trim(),
      recommendations: recs.text.trim(),
      followUp: followUp,
      followUpText: _rep?.followUpText,
    );
    r.reanalyze();
    return r;
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      toast(context, 'Podaj tytuł dokumentu');
      return;
    }
    setState(() => saving = true);
    final db = AppDb.I;
    final ex = widget.existing;
    final doc = MedDocument(
      id: ex?.id,
      profileId: widget.profile.id!,
      date: date,
      title: title.text.trim(),
      category: category,
      facility: facility.text.trim().isEmpty ? null : facility.text.trim(),
      doctor: doctor.text.trim().isEmpty ? null : doctor.text.trim(),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      extractedText: widget.text.trim().isEmpty ? ex?.extractedText : widget.text,
      created: ex?.created ?? DateTime.now(),
      favorite: ex?.favorite ?? false,
      report: _buildReport()?.toJson(),
      followUp: followUp,
    );
    final id = await db.saveDocument(doc);
    if (ex == null) {
      for (final f in widget.files) {
        await Storage.attach(id, f.path, f.name);
      }
    }
    var n = 1;
    for (var i = 0; i < widget.figures.length; i++) {
      if (!figSel[i]) continue;
      final fg = widget.figures[i];
      await Storage.attachBytes(id, fg.jpg, 'Grafika ${n++} (str. ${fg.page}).jpg', kind: 'figure');
    }
    final list = results
        .where((r) => r.selected && (r.value != null || (r.valueText ?? '').isNotEmpty))
        .map((r) => LabResult(
              profileId: widget.profile.id!,
              documentId: id,
              date: date,
              key: r.key,
              name: r.name,
              value: r.value,
              valueText: r.valueText,
              unit: r.unit,
              refLow: r.refLow,
              refHigh: r.refHigh,
              flag: r.flag,
            ))
        .toList();
    await db.replaceResults(id, list);
    if (!mounted) return;
    if (ex == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: id, profile: widget.profile)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _edit(int? index) async {
    final r = index == null ? null : results[index];
    final out = await showResultEditor(context, initial: r, sex: widget.profile.sex);
    if (out == null) return;
    setState(() {
      if (index == null) {
        results.add(out);
      } else {
        results[index] = out;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = results.where((r) => r.selected).length;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Sprawdź i zapisz' : 'Ponowna analiza'),
        actions: [
          if (widget.files.isNotEmpty)
            IconButton(
              tooltip: 'Podgląd oryginału',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FileViewerScreen(path: widget.files.first.path, name: widget.files.first.name)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(results.isEmpty ? 'Zapisz dokument' : 'Zapisz dokument i $selected wyników'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Tytuł')),
            gap,
            Row(children: [
              Expanded(child: DateField(label: 'Data badania', value: date, onChanged: (d) => setState(() => date = d))),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: DocCategories.all.contains(category) ? category : DocCategories.other,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rodzaj'),
                  items: [for (final c in DocCategories.all) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
              ),
            ]),
            gap,
            TextField(controller: facility, decoration: const InputDecoration(labelText: 'Placówka / laboratorium')),
            gap,
            TextField(controller: doctor, decoration: const InputDecoration(labelText: 'Lekarz (opcjonalnie)')),
            gap,
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notatki'), maxLines: null),
          ]),
        ),
        if (widget.files.isNotEmpty || widget.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              [
                if (widget.files.isNotEmpty) 'Pliki: ${widget.files.length}',
                if (widget.usedOcr) 'tekst rozpoznany ze skanu (OCR)',
                if (widget.parsed.date != null) 'data z dokumentu: ${fmtDate(widget.parsed.date)}',
              ].join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (showReport) ..._reportSection(context) else
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => setState(() => showReport = true), icon: const Icon(Icons.notes, size: 18), label: const Text('Dodaj opis lekarza')),
            ),
          ),
        if (widget.figures.isNotEmpty) ...[
          SectionTitle('Wykryte grafiki (${figSel.where((e) => e).length}/${widget.figures.length})'),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.figures.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (c, i) => GestureDetector(
                onTap: () => setState(() => figSel[i] = !figSel[i]),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Opacity(
                      opacity: figSel[i] ? 1 : 0.35,
                      child: Image.memory(widget.figures[i].jpg, height: 150, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(figSel[i] ? Icons.check_circle : Icons.radio_button_unchecked, color: figSel[i] ? cs.primary : cs.outline),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('Zaznaczone grafiki zostaną zapisane przy dokumencie. Inne fragmenty możesz wyciąć później w podglądzie pliku.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
        SectionTitle(
          results.isEmpty ? 'Wyniki' : 'Rozpoznane wyniki ($selected z ${results.length})',
          trailing: TextButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add, size: 18), label: const Text('Dodaj')),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.files.isEmpty
                  ? 'Dodaj parametry przyciskiem „Dodaj”.'
                  : 'Nie znaleziono wartości liczbowych w znanym formacie. To normalne dla opisów (USG, RTG, wypisy). '
                      'Parametry laboratoryjne możesz dodać ręcznie.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Porównaj z oryginałem – stuknij wiersz, aby poprawić. Odznaczone nie zostaną zapisane.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        for (var i = 0; i < results.length; i++) _row(i),
        if (widget.text.trim().isNotEmpty)
          ExpansionTile(
            title: const Text('Rozpoznany tekst'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [SelectableText(widget.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))],
          ),
      ]),
    );
  }

  List<Widget> _reportSection(BuildContext context) {
    final abn = (_rep?.findings ?? []).where((f) => f.abnormal).toList();
    const gap = SizedBox(height: 12);
    return [
      SectionTitle(_rep?.examName == null ? 'Opis lekarza' : 'Opis lekarza – ${_rep!.examName}'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_rep?.isEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Nie udało się wydzielić opisu – możesz go wpisać lub wkleić z „Rozpoznanego tekstu” poniżej.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          TextField(controller: conc, maxLines: null, decoration: const InputDecoration(labelText: 'Wnioski / rozpoznanie')),
          gap,
          TextField(controller: desc, maxLines: null, minLines: 2, decoration: const InputDecoration(labelText: 'Opis badania')),
          gap,
          TextField(controller: recs, maxLines: null, decoration: const InputDecoration(labelText: 'Zalecenia')),
          gap,
          Row(children: [
            Expanded(child: DateField(label: 'Zalecona kontrola do', value: followUp, onChanged: (d) => setState(() => followUp = d))),
            if (followUp != null) IconButton(onPressed: () => setState(() => followUp = null), icon: const Icon(Icons.clear), tooltip: 'Bez terminu'),
          ]),
          if (_rep?.followUpText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('Na podstawie: „${_rep!.followUpText}”', style: Theme.of(context).textTheme.bodySmall),
            ),
          if (abn.isNotEmpty) ...[
            gap,
            Text('Wykryte istotne zapisy (${abn.length}):', style: Theme.of(context).textTheme.labelLarge),
            for (final f in abn.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.priority_high, size: 16, color: StatusColors.warn(context)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f.sentence, style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
          ],
        ]),
      ),
    ];
  }

  Widget _row(int i) {
    final r = results[i];
    final p = LabDictionary.get(r.key);
    final lo = r.refLow ?? (r.refHigh == null ? p?.lowFor(widget.profile.sex) : null);
    final hi = r.refHigh ?? (r.refLow == null ? p?.highFor(widget.profile.sex) : null);
    final st = statusOf(r.value, lo, hi, r.flag);
    return CheckboxListTile(
      value: r.selected,
      onChanged: (v) => setState(() => r.selected = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Row(children: [
        Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600))),
        if (!r.known)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('nowy', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.tertiary)),
          ),
      ]),
      subtitle: Text('norma ${refText(lo, hi)}${r.refLow == null && r.refHigh == null && (lo != null || hi != null) ? ' (domyślna)' : ''}'),
      secondary: InkWell(
        onTap: () => _edit(i),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtValue(r.value, r.valueText), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: StatusColors.of(context, st))),
            Text(r.unit, style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.edit_outlined, size: 18),
        ]),
      ),
    );
  }
}

String refText(double? lo, double? hi) {
  if (lo != null && hi != null) return '${fmtNum(lo)}–${fmtNum(hi)}';
  if (hi != null) return '≤ ${fmtNum(hi)}';
  if (lo != null) return '≥ ${fmtNum(lo)}';
  return '–';
}

/// Dialog edycji / dodania jednego wyniku.
Future<ParsedResult?> showResultEditor(BuildContext context, {ParsedResult? initial, String? sex, String? fixedKey}) {
  return showModalBottomSheet<ParsedResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _ResultEditor(initial: initial, sex: sex, fixedKey: fixedKey),
    ),
  );
}

class _ResultEditor extends StatefulWidget {
  final ParsedResult? initial;
  final String? sex;
  final String? fixedKey;
  const _ResultEditor({this.initial, this.sex, this.fixedKey});
  @override
  State<_ResultEditor> createState() => _ResultEditorState();
}

class _ResultEditorState extends State<_ResultEditor> {
  late LabParam? param = LabDictionary.get(widget.fixedKey ?? widget.initial?.key ?? '');
  late final name = TextEditingController(text: widget.initial?.name ?? param?.name ?? '');
  late final value = TextEditingController(text: widget.initial?.valueText ?? (widget.initial?.value == null ? '' : fmtNum(widget.initial!.value, maxDecimals: 4)));
  late final unit = TextEditingController(text: widget.initial?.unit ?? param?.unit ?? '');
  late final low = TextEditingController(text: widget.initial?.refLow == null ? '' : fmtNum(widget.initial!.refLow, maxDecimals: 4));
  late final high = TextEditingController(text: widget.initial?.refHigh == null ? '' : fmtNum(widget.initial!.refHigh, maxDecimals: 4));

  Future<void> _pickParam() async {
    final p = await showSearch<LabParam?>(context: context, delegate: ParamSearch());
    if (p == null) return;
    setState(() {
      param = p;
      name.text = p.name;
      if (unit.text.trim().isEmpty) unit.text = p.unit;
    });
  }

  void _ok() {
    final raw = value.text.trim();
    final v = parseNum(raw.replaceAll(RegExp(r'^[<>≤≥]=?'), ''));
    if (name.text.trim().isEmpty || raw.isEmpty) {
      toast(context, 'Podaj nazwę i wartość');
      return;
    }
    final known = param != null && normText(param!.name) == normText(name.text);
    final p = known ? param : LabDictionary.findByName(name.text);
    final isText = v == null || RegExp(r'^[<>≤≥]').hasMatch(raw);
    Navigator.pop(
      context,
      ParsedResult(
        key: p?.key ?? 'X:${normText(name.text)}',
        name: p?.name ?? name.text.trim(),
        value: v,
        valueText: isText ? raw : null,
        unit: unit.text.trim(),
        refLow: parseNum(low.text),
        refHigh: parseNum(high.text),
        flag: widget.initial?.flag,
        known: p != null,
        rawLine: widget.initial?.rawLine ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.initial == null ? 'Dodaj wynik' : 'Popraw wynik', style: Theme.of(context).textTheme.titleMedium),
        if ((widget.initial?.rawLine ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Z dokumentu: ${widget.initial!.rawLine}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        ],
        gap,
        TextField(
          controller: name,
          enabled: widget.fixedKey == null,
          decoration: InputDecoration(
            labelText: 'Parametr',
            suffixIcon: widget.fixedKey == null ? IconButton(icon: const Icon(Icons.search), tooltip: 'Wybierz z listy', onPressed: _pickParam) : null,
          ),
        ),
        gap,
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: value,
              autofocus: widget.initial == null && widget.fixedKey != null,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(labelText: 'Wynik', helperText: 'liczba lub np. „<0,5”, „ujemny”'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Jednostka'))),
        ]),
        gap,
        Row(children: [
          Expanded(
              child: TextField(
                  controller: low, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Norma od'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: high, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Norma do'))),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _ok, child: const Text('Gotowe')),
      ]),
    );
  }
}

class ParamSearch extends SearchDelegate<LabParam?> {
  ParamSearch() : super(searchFieldLabel: 'Szukaj parametru');

  List<LabParam> _filter() {
    final q = normText(query);
    final all = LabDictionary.all();
    if (q.isEmpty) return all;
    return all.where((p) => normText(p.name).contains(q) || p.aliases.any((a) => a.contains(q)) || normText(p.key).contains(q)).toList();
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const BackButtonIcon());

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final l = _filter();
    return ListView.builder(
      itemCount: l.length,
      itemBuilder: (c, i) => ListTile(
        title: Text(l[i].name),
        subtitle: Text('${l[i].category}${l[i].unit.isEmpty ? '' : ' • ${l[i].unit}'}'),
        onTap: () => close(context, l[i]),
      ),
    );
  }
}

class ParsedResultX {
  static ParsedResult fromLab(LabResult r) => ParsedResult(
        key: r.key,
        name: r.name,
        value: r.value,
        valueText: r.valueText,
        unit: r.unit,
        refLow: r.refLow,
        refHigh: r.refHigh,
        flag: r.flag,
        known: LabDictionary.get(r.key) != null,
      );
}
