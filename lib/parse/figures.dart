// Wykrywanie grafik (wykresy, zdjęcia USG, zapisy EKG) na zeskanowanej stronie.
// Idea: strona -> siatka komórek; komórki z "atramentem", które nie są pokryte tekstem z OCR,
// łączymy w obszary; duże obszary o rozsądnej gęstości to grafiki do wycięcia.

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class BoxF {
  final double l, t, r, b;
  const BoxF(this.l, this.t, this.r, this.b);
  double get w => r - l;
  double get h => b - t;
  double get area => max(0, w) * max(0, h);
}

class FigureCrop {
  final Uint8List jpg;
  final BoxF box; // w pikselach strony
  final int page;
  FigureCrop(this.jpg, this.box, this.page);
}

class _Req {
  final Uint8List png;
  final List<List<double>> textBoxes;
  final int page;
  _Req(this.png, this.textBoxes, this.page);
}

class FigureDetector {
  /// Zwraca wycięte grafiki ze strony. [textBoxes] w pikselach obrazu [png].
  static Future<List<FigureCrop>> detect(Uint8List png, List<BoxF> textBoxes, {int page = 0}) async {
    final req = _Req(png, textBoxes.map((b) => [b.l, b.t, b.r, b.b]).toList(), page);
    try {
      return await Isolate.run(() => _detect(req));
    } catch (_) {
      return [];
    }
  }

  static List<FigureCrop> _detect(_Req req) {
    final full = img.decodeImage(req.png);
    if (full == null) return [];
    final page = img.bakeOrientation(full);
    final W = page.width, H = page.height;
    const cols = 160;
    final cell = W / cols;
    final rows = (H / cell).ceil();
    final small = img.copyResize(page, width: cols, height: rows, interpolation: img.Interpolation.average);

    // jasność tła = 90. percentyl jasności (papier ze skanu bywa szary)
    final lum = List<double>.filled(cols * rows, 0);
    final sat = List<double>.filled(cols * rows, 0);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        lum[y * cols + x] = 0.299 * r + 0.587 * g + 0.114 * b;
        sat[y * cols + x] = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
      }
    }
    final sorted = List<double>.of(lum)..sort();
    final bg = sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];

    final ink = List<bool>.filled(cols * rows, false);
    for (var i = 0; i < ink.length; i++) {
      ink[i] = lum[i] < bg - 18 || sat[i] > 40;
    }
    // maska tekstu (z marginesem 1 komórki)
    final text = List<bool>.filled(cols * rows, false);
    for (final tb in req.textBoxes) {
      final x0 = max(0, (tb[0] / cell).floor() - 1), x1 = min(cols - 1, (tb[2] / cell).ceil());
      final y0 = max(0, (tb[1] / cell).floor() - 1), y1 = min(rows - 1, (tb[3] / cell).ceil());
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          text[y * cols + x] = true;
        }
      }
    }
    final cand = List<bool>.generate(ink.length, (i) => ink[i] && !text[i]);

    // dylatacja – łączy cienkie linie wykresów i fragmenty zdjęć
    final dil = List<bool>.filled(cand.length, false);
    const d = 2;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (!cand[y * cols + x]) continue;
        for (var yy = max(0, y - d); yy <= min(rows - 1, y + d); yy++) {
          for (var xx = max(0, x - d); xx <= min(cols - 1, x + d); xx++) {
            dil[yy * cols + xx] = true;
          }
        }
      }
    }

    // składowe spójne
    final label = List<int>.filled(dil.length, 0);
    final comps = <List<int>>[]; // [x0,y0,x1,y1,count]
    var next = 1;
    final stack = <int>[];
    for (var i = 0; i < dil.length; i++) {
      if (!dil[i] || label[i] != 0) continue;
      var x0 = cols, y0 = rows, x1 = 0, y1 = 0, count = 0;
      stack.add(i);
      label[i] = next;
      while (stack.isNotEmpty) {
        final k = stack.removeLast();
        final x = k % cols, y = k ~/ cols;
        if (cand[k]) count++;
        x0 = min(x0, x);
        y0 = min(y0, y);
        x1 = max(x1, x);
        y1 = max(y1, y);
        for (final n in [k - 1, k + 1, k - cols, k + cols]) {
          if (n < 0 || n >= dil.length) continue;
          if ((n == k - 1 && x == 0) || (n == k + 1 && x == cols - 1)) continue;
          if (dil[n] && label[n] == 0) {
            label[n] = next;
            stack.add(n);
          }
        }
      }
      comps.add([x0, y0, x1, y1, count]);
      next++;
    }

    final out = <FigureCrop>[];
    final pageCells = cols * rows;
    for (final c in comps) {
      final bw = c[2] - c[0] + 1, bh = c[3] - c[1] + 1;
      final area = bw * bh;
      if (area < pageCells * 0.02) continue; // za małe (logo, pieczątka, podpis)
      if (area > pageCells * 0.75) continue; // całe tło strony
      if (bw < cols * 0.15 || bh < rows * 0.05) continue; // linie, kreski tabel
      final density = c[4] / area;
      if (density < 0.08) continue;
      // ile tekstu w środku – tabele i formularze odrzucamy
      var textCells = 0;
      for (var y = c[1]; y <= c[3]; y++) {
        for (var x = c[0]; x <= c[2]; x++) {
          if (text[y * cols + x]) textCells++;
        }
      }
      if (textCells / area > 0.35) continue;

      final pad = 1;
      final bx = BoxF(max(0, (c[0] - pad) * cell), max(0, (c[1] - pad) * cell), min(W.toDouble(), (c[2] + 1 + pad) * cell), min(H.toDouble(), (c[3] + 1 + pad) * cell));
      final crop = img.copyCrop(page, x: bx.l.round(), y: bx.t.round(), width: bx.w.round(), height: bx.h.round());
      out.add(FigureCrop(Uint8List.fromList(img.encodeJpg(crop, quality: 88)), bx, req.page));
    }
    out.sort((a, b) => a.box.t.compareTo(b.box.t));
    return out.take(6).toList();
  }

  /// Ręczne wycięcie fragmentu (współrzędne względne 0..1).
  static Future<Uint8List?> cropRelative(Uint8List imageBytes, double l, double t, double r, double b) async {
    return Isolate.run(() {
      final im = img.decodeImage(imageBytes);
      if (im == null) return null;
      final o = img.bakeOrientation(im);
      final x = (l * o.width).round().clamp(0, o.width - 1);
      final y = (t * o.height).round().clamp(0, o.height - 1);
      final w = ((r - l) * o.width).round().clamp(1, o.width - x);
      final h = ((b - t) * o.height).round().clamp(1, o.height - y);
      return Uint8List.fromList(img.encodeJpg(img.copyCrop(o, x: x, y: y, width: w, height: h), quality: 90));
    });
  }

  /// Obraca zdjęcie zgodnie z EXIF i zapisuje jako PNG (spójne współrzędne dla OCR i wycinania).
  static Future<Uint8List?> normalizeImage(Uint8List bytes) async {
    return Isolate.run(() {
      final im = img.decodeImage(bytes);
      if (im == null) return null;
      var o = img.bakeOrientation(im);
      if (o.width > 2600) o = img.copyResize(o, width: 2600);
      return Uint8List.fromList(img.encodePng(o, level: 1));
    });
  }
}
