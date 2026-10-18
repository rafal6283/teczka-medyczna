import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../parse/lab_dictionary.dart';
import '../parse/lab_parser.dart';
import '../parse/text_utils.dart';
import 'common.dart';
import 'import_flow.dart';
import 'params.dart';
import 'review.dart';
import 'viewer.dart';

IconData categoryIcon(String c) {
  switch (c) {
    case DocCategories.lab:
      return Icons.science_outlined;
    case DocCategories.imaging:
      return Icons.image_search;
    case DocCategories.functional:
      return Icons.monitor_heart_outlined;
    case DocCategories.visit:
      return Icons.medical_services_outlined;
    case DocCategories.prescription:
      return Icons.receipt_long_outlined;
    case DocCategories.vaccine:
      return Icons.vaccines_outlined;
    default:
      return Icons.description_outlined;
  }
}

class _DocData {
  final List<MedDocument> docs;
  final Map<int, int> files, results;
  _DocData(this.docs, this.files, this.results);
}

class DocumentsTab extends StatefulWidget {
  final Profile profile;
  const DocumentsTab({super.key, required this.profile});
  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  String query = '';
  String? cat;
  final ctrl = TextEditingController();

  Future<_DocData> _load() async {
    final db = AppDb.I;
    final id = widget.profile.id!;
    final docs = query.trim().isEmpty ? await db.getDocuments(id) : await db.searchDocuments(id, query.trim());
    return _DocData(docs, await db.fileCounts(id), await db.resultCounts(id));
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<_DocData>(
      dep: '${widget.profile.id}|$query',
      load: _load,
      builder: (context, d) {
        final cats = d.docs.map((e) => e.category).toSet();
        final docs = d.docs.where((e) => cat == null || e.category == cat).toList();
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchBar(
                controller: ctrl,
                hintText: 'Szukaj w dokumentach i ich treści',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                trailing: [
                  if (query.isNotEmpty)
                    IconButton(
                        onPressed: () {
                          ctrl.clear();
                          setState(() => query = '');
                        },
                        icon: const Icon(Icons.clear)),
                ],
                onChanged: (v) => setState(() => query = v),
              ),
            ),
          ),
          if (cats.length > 1)
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  for (final c in DocCategories.all.where(cats.contains))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c),
                        selected: cat == c,
                        onSelected: (s) => setState(() => cat = s ? c : null),
                      ),
                    ),
                ]),
              ),
            ),
          if (docs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.folder_open,
                title: query.isEmpty ? 'Brak dokumentów' : 'Nic nie znaleziono',
                text: query.isEmpty ? 'Dodaj pierwszy wynik przyciskiem „Dodaj wynik”: PDF, skan lub zdjęcie.' : 'Spróbuj innego słowa.',
              ),
            )
          else
            SliverList.builder(
              itemCount: docs.length,
              itemBuilder: (c, i) {
                final doc = docs[i];
                final showYear = i == 0 || docs[i - 1].date.year != doc.date.year;
                final fc = d.files[doc.id] ?? 0;
                final rc = d.results[doc.id] ?? 0;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (showYear) SectionTitle('${doc.date.year}'),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(categoryIcon(doc.category), color: Theme.of(context).colorScheme.onSecondaryContainer),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (doc.favorite) const Icon(Icons.star, size: 16, color: Colors.amber),
                    ]),
                    subtitle: Text([
                      fmtDate(doc.date),
                      if (doc.facility != null) doc.facility!,
                      if (rc > 0) '$rc wyn.',
                      if (fc > 0) '$fc ${fc == 1 ? 'plik' : 'pliki'}',
                    ].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(documentId: doc.id!, profile: widget.profile))),
                  ),
                ]);
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ]);
      },
    );
  }
}

class _DocDetail {
  final MedDocument doc;
  final List<DocFile> files;
  final List<LabResult> results;
  _DocDetail(this.doc, this.files, this.results);
}

class DocumentScreen extends StatelessWidget {
  final int documentId;
  final Profile profile;
  const DocumentScreen({super.key, required this.documentId, required this.profile});

  Future<_DocDetail?> _load() async {
    final db = AppDb.I;
    final d = await db.getDocument(documentId);
    if (d == null) return null;
    return _DocDetail(d, await db.getFiles(documentId), await db.getResults(profile.id!, documentId: documentId));
  }

  Future<void> _reanalyze(BuildContext context, _DocDetail d) async {
    final sources = d.files.where((f) => !f.isGraphic).toList();
    if (sources.isEmpty) {
      toast(context, 'Brak pliku do analizy');
      return;
    }
    if (d.results.isNotEmpty &&
        !await confirm(context, 'Odczytać ponownie?', 'Obecne wyniki tego dokumentu zostaną zastąpione nowo rozpoznanymi (po Twojej weryfikacji).', ok: 'Odczytaj', destructive: false)) {
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          profile: profile,
          files: sources.map((f) => PickedFile(AppDb.I.absPath(f.path), f.name)).toList(),
          existing: d.doc,
        ),
      ),
    );
  }

  Future<void> _editMeta(BuildContext context, MedDocument doc) async {
    // edycja metadanych przez ekran weryfikacji bez plików i z bieżącymi wynikami
    final results = await AppDb.I.getResults(profile.id!, documentId: doc.id);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          profile: profile,
          files: const [],
          parsed: ParseOutput(
            results
                .map((r) => ParsedResult(
                    key: r.key,
                    name: r.name,
                    value: r.value,
                    valueText: r.valueText,
                    unit: r.unit,
                    refLow: r.refLow,
                    refHigh: r.refHigh,
                    flag: r.flag,
                    known: LabDictionary.get(r.key) != null))
                .toList(),
            doc.date,
            doc.facility,
            doc.category,
            doc.title,
          ),
          text: '',
          usedOcr: false,
          figures: const [],
          existing: doc,
        ),
      ),
    );
  }

  Future<void> _addFiles(BuildContext context, MedDocument doc) async {
    final r = await pickAnyFiles();
    for (final f in r) {
      await Storage.attach(doc.id!, f.path, f.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<_DocDetail?>(
      load: _load,
      builder: (context, d) {
        if (d == null) return const Scaffold(body: Center(child: Text('Dokument usunięty')));
        final doc = d.doc;
        final sources = d.files.where((f) => !f.isGraphic).toList();
        final graphics = d.files.where((f) => f.isGraphic).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(doc.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: doc.favorite ? 'Usuń z ważnych' : 'Oznacz jako ważny',
                icon: Icon(doc.favorite ? Icons.star : Icons.star_border),
                onPressed: () => AppDb.I.saveDocument(doc.copyWith(favorite: !doc.favorite)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') await _editMeta(context, doc);
                  if (v == 'reparse' && context.mounted) await _reanalyze(context, d);
                  if (v == 'add' && context.mounted) await _addFiles(context, doc);
                  if (v == 'delete' && context.mounted) {
                    if (await confirm(context, 'Usunąć dokument?', 'Usunięte zostaną pliki i ${d.results.length} wyników z tego dokumentu.')) {
                      await AppDb.I.deleteDocument(doc.id!);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edytuj dane i wyniki')),
                  PopupMenuItem(value: 'reparse', child: Text('Odczytaj wyniki ponownie')),
                  PopupMenuItem(value: 'add', child: Text('Dołącz plik')),
                  PopupMenuItem(value: 'delete', child: Text('Usuń dokument')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            InfoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(categoryIcon(doc.category), size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(doc.category, style: Theme.of(context).textTheme.labelLarge),
                ]),
                const SizedBox(height: 10),
                _kv(context, 'Data', fmtDate(doc.date)),
                if (doc.facility != null) _kv(context, 'Placówka', doc.facility!),
                if (doc.doctor != null) _kv(context, 'Lekarz', doc.doctor!),
                if (doc.notes != null) ...[const SizedBox(height: 6), Text(doc.notes!)],
              ]),
            ),
            if (sources.isNotEmpty) ...[
              const SectionTitle('Pliki'),
              for (final f in sources)
                ListTile(
                  leading: Icon(f.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${(f.size / 1024).toStringAsFixed(0)} KB'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, 'Usunąć plik?', f.name)) await AppDb.I.deleteFile(f);
                    },
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FileViewerScreen(path: AppDb.I.absPath(f.path), name: f.name, documentId: doc.id)),
                  ),
                ),
            ],
            if (graphics.isNotEmpty) ...[
              const SectionTitle('Grafiki i wycinki'),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: graphics.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (c, i) {
                    final g = graphics[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FileViewerScreen(path: AppDb.I.absPath(g.path), name: g.name)),
                      ),
                      onLongPress: () async {
                        if (await confirm(context, 'Usunąć grafikę?', g.name)) await AppDb.I.deleteFile(g);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(AppDb.I.absPath(g.path)), height: 140, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text('Przytrzymaj, aby usunąć. Nowy wycinek: otwórz plik i użyj ikony nożyczek.', style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            SectionTitle('Wyniki (${d.results.length})'),
            if (d.results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  sources.isEmpty ? 'Brak wyników.' : 'Brak odczytanych wartości. Użyj menu „Odczytaj wyniki ponownie” albo „Edytuj dane i wyniki”.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            for (final r in d.results) ResultTile(result: r, profile: profile),
          ]),
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 80, child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(v)),
        ]),
      );
}

class ResultTile extends StatelessWidget {
  final LabResult result;
  final Profile profile;
  const ResultTile({super.key, required this.result, required this.profile});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final p = LabDictionary.get(r.key);
    final hasOwn = r.refLow != null || r.refHigh != null;
    final lo = hasOwn ? r.refLow : p?.lowFor(profile.sex);
    final hi = hasOwn ? r.refHigh : p?.highFor(profile.sex);
    final st = statusOf(r.value, lo, hi, r.flag);
    return ListTile(
      dense: true,
      leading: StatusDot(st),
      minLeadingWidth: 12,
      title: Text(r.name),
      subtitle: Text('norma ${refText(lo, hi)}'),
      trailing: Text('${fmtValue(r.value, r.valueText)} ${r.unit}',
          style: TextStyle(fontWeight: FontWeight.w700, color: StatusColors.of(context, st), fontSize: 14)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParamDetailScreen(profile: profile, paramKey: r.key))),
    );
  }
}

Future<List<PickedFile>> pickAnyFiles() async {
  final r = await pickFilesRaw();
  return r;
}
