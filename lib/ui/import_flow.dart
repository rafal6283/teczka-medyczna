import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../data/storage.dart';
import '../parse/extractor.dart';
import '../parse/figures.dart';
import '../parse/lab_parser.dart';
import '../parse/report_parser.dart';
import 'common.dart';
import 'review.dart';

class PickedFile {
  final String path;
  final String name;
  PickedFile(this.path, this.name);
  bool get isPdf => name.toLowerCase().endsWith('.pdf');
}

Future<void> startImport(BuildContext context, Profile profile) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Dodaj wynik badania')),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Plik PDF lub obraz'),
          subtitle: const Text('Z pamięci telefonu, poczty, Dysku'),
          onTap: () => Navigator.pop(c, 'file'),
        ),
        ListTile(
          leading: const Icon(Icons.document_scanner_outlined),
          title: const Text('Zeskanuj papierowy wynik'),
          subtitle: const Text('Aparat z wykrywaniem krawędzi kartki'),
          onTap: () => Navigator.pop(c, 'scan'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Zdjęcia z galerii'),
          onTap: () => Navigator.pop(c, 'gallery'),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: const Text('Wpisz wyniki ręcznie'),
          subtitle: const Text('Bez pliku'),
          onTap: () => Navigator.pop(c, 'manual'),
        ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;

  final files = <PickedFile>[];
  try {
    switch (choice) {
      case 'file':
        files.addAll(await pickFilesRaw());
        break;
      case 'scan':
        final pics = await CunningDocumentScanner.getPictures() ?? <String>[];
        var i = 1;
        for (final path in pics) {
          files.add(PickedFile(path, 'Skan strona ${i++}${p.extension(path).isEmpty ? '.jpg' : p.extension(path)}'));
        }
        break;
      case 'gallery':
        final pics = await ImagePicker().pickMultiImage(imageQuality: 95);
        for (final x in pics) {
          files.add(PickedFile(x.path, x.name));
        }
        break;
      case 'manual':
        break;
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Nie udało się pobrać pliku: $e');
    return;
  }
  if (choice != 'manual' && files.isEmpty) return;
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ProcessingScreen(profile: profile, files: files)));
}

Future<List<PickedFile>> pickFilesRaw() async {
  final r = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
  );
  return [
    for (final f in r?.files ?? <PlatformFile>[])
      if (f.path != null) PickedFile(f.path!, f.name),
  ];
}

/// Odczyt tekstu, OCR, wykrywanie grafik i parsowanie – potem ekran weryfikacji.
class ProcessingScreen extends StatefulWidget {
  final Profile profile;
  final List<PickedFile> files;
  final MedDocument? existing; // ponowna analiza istniejącego dokumentu
  const ProcessingScreen({super.key, required this.profile, required this.files, this.existing});
  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String status = 'Przygotowanie…';
  int done = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final texts = <String>[];
    final figures = <FigureCrop>[];
    var ocr = false;
    for (final f in widget.files) {
      if (!mounted) return;
      setState(() => status = 'Plik ${done + 1} z ${widget.files.length}: ${f.name}');
      try {
        final mime = Storage.mimeFor(f.name);
        ExtractResult r;
        if (f.isPdf) {
          r = await Extractor.fromPdf(f.path, onStatus: (s) => mounted ? setState(() => status = s) : null);
        } else if (mime.startsWith('image/') || mime == 'application/octet-stream') {
          r = await Extractor.fromImage(f.path, onStatus: (s) => mounted ? setState(() => status = s) : null);
        } else {
          r = ExtractResult('', false, 0, []);
        }
        texts.add(r.text);
        figures.addAll(r.figures);
        ocr = ocr || r.usedOcr;
      } catch (e) {
        texts.add('');
      }
      done++;
    }
    final text = texts.join('\n');
    var parsed = LabParser.parse(text);
    final report = ReportParser.parse(text, docDate: parsed.date);
    // opisowe badanie (endoskopia, Holter, obrazowe…) – kategoria i tytuł z rodzaju badania
    final labCount = parsed.results.where((r) => r.known && !r.key.startsWith('HR_') && r.key != 'SVE' && r.key != 'VE' && !r.key.startsWith('PAUSE')).length;
    if (report.examType != null && labCount < 5) {
      parsed = ParseOutput(parsed.results, parsed.date, parsed.facility, categoryForExam(report.examType!), report.examName ?? parsed.suggestedTitle);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          profile: widget.profile,
          files: widget.files,
          parsed: parsed,
          text: text,
          usedOcr: ocr,
          figures: figures,
          existing: widget.existing,
          report: report,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.isEmpty ? 1 : widget.files.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Analiza dokumentu')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: widget.files.isEmpty ? null : (done + 0.3) / total)),
            const SizedBox(height: 24),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text('Wszystko dzieje się na telefonie – dane nigdzie nie są wysyłane.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

String categoryForExam(String key) {
  switch (key) {
    case 'COLONO':
    case 'GASTRO':
      return DocCategories.endoscopy;
    case 'HOLTER_EKG':
    case 'ABPM':
    case 'EKG':
    case 'ERGO':
    case 'SPIRO':
    case 'ECHO':
      return DocCategories.functional;
    case 'HIST':
    case 'CYTO':
      return DocCategories.histo;
    case 'WYPIS':
    case 'KONS':
      return DocCategories.visit;
    default:
      return DocCategories.imaging;
  }
}

/// Plik z dokumentu → PickedFile (do ponownej analizy).
PickedFile pickedFromStored(String absPath, String name) => PickedFile(absPath, name);

bool fileExists(String path) => File(path).existsSync();
