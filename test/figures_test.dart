import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:teczka_zdrowia/parse/figures.dart';

void main() {
  test('Wykrywa wykres i zdjęcie, pomija wiersze tekstu', () async {
    final page = img.Image(width: 1000, height: 1400);
    img.fill(page, color: img.ColorRgb8(250, 250, 248));
    final textBoxes = <BoxF>[];
    // 12 wierszy "tekstu" u góry
    for (var i = 0; i < 12; i++) {
      final y = 60 + i * 34;
      img.fillRect(page, x1: 80, y1: y, x2: 700, y2: y + 16, color: img.ColorRgb8(30, 30, 30));
      textBoxes.add(BoxF(80, y.toDouble(), 700, y + 16.0));
    }
    // wykres: osie + łamana + słupki
    img.drawLine(page, x1: 120, y1: 560, x2: 120, y2: 900, color: img.ColorRgb8(0, 0, 0), thickness: 3);
    img.drawLine(page, x1: 120, y1: 900, x2: 880, y2: 900, color: img.ColorRgb8(0, 0, 0), thickness: 3);
    var px = 130, py = 850;
    for (var i = 0; i < 15; i++) {
      final nx = px + 50, ny = 650 + (i * 37) % 220;
      img.drawLine(page, x1: px, y1: py, x2: nx, y2: ny, color: img.ColorRgb8(200, 20, 20), thickness: 4);
      img.fillRect(page, x1: px + 10, y1: 900 - (i * 13) % 150, x2: px + 30, y2: 900, color: img.ColorRgb8(60, 90, 200));
      px = nx;
      py = ny;
    }
    // "zdjęcie USG" – ciemny prostokąt z szumem
    for (var y = 980; y < 1320; y++) {
      for (var x = 200; x < 760; x++) {
        final v = ((x * 7 + y * 13) % 90) + 20;
        page.setPixelRgb(x, y, v, v, v);
      }
    }
    final png = Uint8List.fromList(img.encodePng(page));
    final figs = await FigureDetector.detect(png, textBoxes, page: 1);
    expect(figs.length, 2);
    expect(figs[0].box.t, lessThan(600));
    expect(figs[0].box.b, greaterThan(880));
    expect(figs[1].box.t, greaterThan(940));
    expect(figs[1].box.w, greaterThan(500));
  });

  test('Strona z samym tekstem nie daje grafik', () async {
    final page = img.Image(width: 1000, height: 1400);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final boxes = <BoxF>[];
    for (var i = 0; i < 30; i++) {
      final y = 60 + i * 40;
      img.fillRect(page, x1: 80, y1: y, x2: 900, y2: y + 18, color: img.ColorRgb8(20, 20, 20));
      boxes.add(BoxF(80, y.toDouble(), 900, y + 18.0));
    }
    final figs = await FigureDetector.detect(Uint8List.fromList(img.encodePng(page)), boxes);
    expect(figs, isEmpty);
  });
}
