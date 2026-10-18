import 'package:flutter_test/flutter_test.dart';
import 'package:teczka_zdrowia/parse/extractor.dart';

void main() {
  test('Rozpoznaje zepsutą warstwę tekstu PDF', () {
    const garbage = '<(+ /+ .(+ 0 +%+ *:/ 1&F ( %\$ "2A ,-, ,4 A 969=0; #:;10:DP!8 II 1:8Q#96C@!8 68 ;1@=0#;';
    const good = 'Hemoglobina 14,8 g/dl 13,5 - 17,5\nCholesterol całkowity 215 mg/dl < 190\nData pobrania materiału 12.03.2025';
    expect(Extractor.textQuality(garbage), lessThan(0.2));
    expect(Extractor.textQuality(good), greaterThan(0.3));
  });
}
