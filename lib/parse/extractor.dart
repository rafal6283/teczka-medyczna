// Wyciąganie tekstu z PDF (warstwa tekstowa) i ze skanów/zdjęć (OCR ML Kit na urządzeniu)
// oraz wykrywanie grafik (wykresy, zdjęcia) na stronach.

import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'figures.dart';

class _Item {
  final int page;
  final double top, bottom, left, right;
  final String text;
  _Item(this.page, this.top, this.bottom, this.left, this.right, this.text);
  double get cy => (top + bottom) / 2;
  double get h => (bottom - top).abs().clamp(1, 1e9).toDouble();
}

class ExtractResult {
  final String text;
  final bool usedOcr;
  final int pages;
  final List<FigureCrop> figures;
  ExtractResult(this.text, this.usedOcr, this.pages, this.figures);
}

class Extractor {
  static const maxPages = 12;
  static const renderWidth = 2200.0;

  /// Składa fragmenty tekstu w wiersze wg położenia (ważne dla tabel w wynikach).
  static String _rows(List<_Item> items) {
    items.sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.cy.compareTo(b.cy));
    final rows = <List<_Item>>[];
    for (final it in items) {
      if (rows.isNotEmpty) {
        final row = rows.last;
        final ref = row.first;
        final tol = (ref.h < it.h ? ref.h : it.h) * 0.55;
        if (ref.page == it.page && (it.cy - ref.cy).abs() <= tol) {
          row.add(it);
          continue;
        }
      }
      rows.add([it]);
    }
    final sb = StringBuffer();
    int? lastPage;
    for (final r in rows) {
      if (lastPage != null && r.first.page != lastPage) sb.writeln();
      lastPage = r.first.page;
      r.sort((a, b) => a.left.compareTo(b.left));
      sb.writeln(r.map((e) => e.text.trim()).where((e) => e.isNotEmpty).join('   '));
    }
    return sb.toString();
  }

  static int _letters(String s) => RegExp(r'\p{L}', unicode: true).allMatches(s).length;

  static final _word = RegExp(r'^[\p{L}]{3,}$', unicode: true);
  static final _vowel = RegExp(r'[aeiouyąęóAEIOUYĄĘÓ]');

  /// Udział "prawdziwych słów" w tekście. PDF-y z czcionkami bez mapy znaków (np. część wyników
  /// Diagnostyki) mają warstwę tekstu złożoną z przypadkowych znaków – wtedy wynik ~0.
  static double textQuality(String t) {
    final nonSpace = t.replaceAll(RegExp(r'\s'), '').length;
    if (nonSpace == 0) return 0;
    var good = 0;
    for (final w in t.split(RegExp(r'\s+'))) {
      final w2 = w.replaceAll(RegExp(r'^[.,:;()]+|[.,:;()]+$'), '');
      if (_word.hasMatch(w2) && _vowel.hasMatch(w2)) good += w2.length;
    }
    return good / nonSpace;
  }

  static Future<(String, List<BoxF>)> _ocrFile(String path, int page) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await recognizer.processImage(InputImage.fromFilePath(path));
      final items = <_Item>[];
      final boxes = <BoxF>[];
      for (final b in res.blocks) {
        for (final l in b.lines) {
          final r = l.boundingBox;
          items.add(_Item(page, r.top, r.bottom, r.left, r.right, l.text));
          boxes.add(BoxF(r.left, r.top, r.right, r.bottom));
        }
      }
      return (_rows(items), boxes);
    } finally {
      await recognizer.close();
    }
  }

  static Future<ExtractResult> fromPdf(String path, {void Function(String)? onStatus, bool findFigures = true}) async {
    final bytes = await File(path).readAsBytes();

    // 1) warstwa tekstowa
    var text = '';
    var pages = 1;
    final pdfItems = <_Item>[];
    final pageSizes = <int, (double, double)>{};
    try {
      onStatus?.call('Odczyt tekstu z PDF…');
      final doc = sf.PdfDocument(inputBytes: bytes);
      pages = doc.pages.count;
      for (var i = 0; i < pages; i++) {
        final s = doc.pages[i].size;
        pageSizes[i] = (s.width, s.height);
      }
      for (final l in sf.PdfTextExtractor(doc).extractTextLines()) {
        pdfItems.add(_Item(l.pageIndex, l.bounds.top, l.bounds.bottom, l.bounds.left, l.bounds.right, l.text));
      }
      text = _rows(List.of(pdfItems));
      doc.dispose();
    } catch (_) {
      text = '';
    }
    final needOcr = _letters(text) < 40 * pages.clamp(1, 3) || textQuality(text) < 0.2;
    if (!needOcr && !findFigures) return ExtractResult(text, false, pages, []);

    // 2) render stron: OCR (gdy skan) i wykrywanie grafik
    final tmp = await getTemporaryDirectory();
    final ocrText = StringBuffer();
    final figures = <FigureCrop>[];
    px.PdfDocument? doc;
    try {
      doc = await px.PdfDocument.openData(bytes);
      final n = doc.pagesCount < maxPages ? doc.pagesCount : maxPages;
      for (var i = 1; i <= n; i++) {
        onStatus?.call(needOcr ? 'Rozpoznawanie tekstu (OCR) – strona $i z $n…' : 'Szukanie wykresów i zdjęć – strona $i z $n…');
        final page = await doc.getPage(i);
        final scale = renderWidth / page.width;
        final im = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: px.PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        await page.close();
        if (im == null) continue;
        var boxes = <BoxF>[];
        if (needOcr) {
          final f = File(p.join(tmp.path, 'ocr_page_$i.png'));
          await f.writeAsBytes(im.bytes);
          final (t, b) = await _ocrFile(f.path, i);
          ocrText.writeln(t);
          boxes = b;
          await f.delete();
        } else {
          // ramki tekstu z PDF (w punktach) przeliczone na piksele renderu
          final sz = pageSizes[i - 1];
          final k = sz == null ? scale : renderWidth / sz.$1;
          boxes = pdfItems.where((e) => e.page == i - 1).map((e) => BoxF(e.left * k, e.top * k, e.right * k, e.bottom * k)).toList();
        }
        if (findFigures) {
          figures.addAll(await FigureDetector.detect(im.bytes, boxes, page: i));
        }
      }
    } catch (_) {
      // render się nie udał – zostaje to, co mamy
    } finally {
      await doc?.close();
    }
    if (needOcr) {
      final o = ocrText.toString();
      final better = textQuality(o) >= textQuality(text) || _letters(o) > _letters(text);
      return ExtractResult(better ? o : text, true, pages, figures);
    }
    return ExtractResult(text, false, pages, figures);
  }

  static Future<ExtractResult> fromImage(String path, {void Function(String)? onStatus, bool findFigures = true}) async {
    onStatus?.call('Rozpoznawanie tekstu ze zdjęcia (OCR)…');
    final tmp = await getTemporaryDirectory();
    final norm = await FigureDetector.normalizeImage(await File(path).readAsBytes());
    if (norm == null) return ExtractResult('', true, 1, []);
    final f = File(p.join(tmp.path, 'ocr_img_${DateTime.now().millisecondsSinceEpoch}.png'));
    await f.writeAsBytes(norm);
    final (text, boxes) = await _ocrFile(f.path, 1);
    var figures = <FigureCrop>[];
    if (findFigures) {
      onStatus?.call('Szukanie wykresów i zdjęć…');
      figures = await FigureDetector.detect(norm, boxes, page: 1);
    }
    await f.delete();
    return ExtractResult(text, true, 1, figures);
  }

  /// Renderuje stronę PDF do obrazu (do ręcznego wycinania fragmentu).
  static Future<Uint8List?> renderPage(String path, int pageNo) async {
    final doc = await px.PdfDocument.openFile(path);
    try {
      final page = await doc.getPage(pageNo);
      final scale = renderWidth / page.width;
      final im = await page.render(width: page.width * scale, height: page.height * scale, format: px.PdfPageImageFormat.png, backgroundColor: '#FFFFFF');
      await page.close();
      return im?.bytes;
    } finally {
      await doc.close();
    }
  }

  static Future<int> pageCount(String path) async {
    final doc = await px.PdfDocument.openFile(path);
    final n = doc.pagesCount;
    await doc.close();
    return n;
  }
}
