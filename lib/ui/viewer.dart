import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';

import '../data/storage.dart';
import '../parse/extractor.dart';
import '../parse/figures.dart';
import 'common.dart';

/// Podgląd PDF / zdjęcia z możliwością wycięcia fragmentu (wykres, zdjęcie) do dokumentu.
class FileViewerScreen extends StatefulWidget {
  final String path;
  final String name;
  final int? documentId; // gdy podany – można zapisywać wycięte fragmenty
  const FileViewerScreen({super.key, required this.path, required this.name, this.documentId});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  PdfControllerPinch? pdf;
  int page = 1;
  int pages = 1;

  bool get isPdf => widget.name.toLowerCase().endsWith('.pdf') || widget.path.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    if (isPdf) {
      pdf = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
    }
  }

  @override
  void dispose() {
    pdf?.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    Uint8List? bytes;
    if (isPdf) {
      bytes = await Extractor.renderPage(widget.path, page);
    } else {
      bytes = await File(widget.path).readAsBytes();
      bytes = await FigureDetector.normalizeImage(bytes);
    }
    if (bytes == null || !mounted) return;
    final rect = await Navigator.push<Rect>(context, MaterialPageRoute(builder: (_) => CropScreen(image: bytes!)));
    if (rect == null) return;
    final out = await FigureDetector.cropRelative(bytes, rect.left, rect.top, rect.right, rect.bottom);
    if (out == null) return;
    await Storage.attachBytes(widget.documentId!, out, 'Wycinek${isPdf ? ' str. $page' : ''}.jpg', kind: 'crop');
    if (mounted) toast(context, 'Zapisano wycinek przy dokumencie');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.documentId != null)
            IconButton(tooltip: 'Wytnij fragment (wykres, zdjęcie)', icon: const Icon(Icons.crop), onPressed: _crop),
          IconButton(
            tooltip: 'Otwórz w innej aplikacji',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => OpenFilex.open(widget.path),
          ),
        ],
      ),
      body: isPdf
          ? Stack(children: [
              PdfViewPinch(
                controller: pdf!,
                onDocumentLoaded: (d) => setState(() => pages = d.pagesCount),
                onPageChanged: (p) => setState(() => page = p),
              ),
              if (pages > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.inverseSurface, borderRadius: BorderRadius.circular(16)),
                      child: Text('$page / $pages', style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface)),
                    ),
                  ),
                ),
            ])
          : InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(widget.path)))),
    );
  }
}

/// Zaznaczanie prostokąta palcem; zwraca Rect we współrzędnych względnych 0..1.
class CropScreen extends StatefulWidget {
  final Uint8List image;
  const CropScreen({super.key, required this.image});
  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  Offset? a, b; // względne
  Size? imgSize;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.image).then((im) {
      if (mounted) setState(() => imgSize = Size(im.width.toDouble(), im.height.toDouble()));
    });
  }

  Rect? get rel {
    if (a == null || b == null) return null;
    return Rect.fromLTRB(min(a!.dx, b!.dx), min(a!.dy, b!.dy), max(a!.dx, b!.dx), max(a!.dy, b!.dy));
  }

  @override
  Widget build(BuildContext context) {
    final r = rel;
    final valid = r != null && r.width > 0.03 && r.height > 0.02;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zaznacz fragment'),
        actions: [
          TextButton(onPressed: valid ? () => Navigator.pop(context, r) : null, child: const Text('Wytnij')),
        ],
      ),
      body: imgSize == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              const Padding(padding: EdgeInsets.all(12), child: Text('Przeciągnij palcem po obszarze wykresu lub zdjęcia.')),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final s = min(c.maxWidth / imgSize!.width, c.maxHeight / imgSize!.height);
                  final w = imgSize!.width * s, h = imgSize!.height * s;
                  Offset toRel(Offset p) => Offset((p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0));
                  return Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          a = toRel(d.localPosition);
                          b = a;
                        }),
                        onPanUpdate: (d) => setState(() => b = toRel(d.localPosition)),
                        child: Stack(children: [
                          Positioned.fill(child: Image.memory(widget.image, fit: BoxFit.fill)),
                          if (r != null)
                            Positioned(
                              left: r.left * w,
                              top: r.top * h,
                              width: r.width * w,
                              height: r.height * h,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2.5),
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
            ]),
    );
  }
}
