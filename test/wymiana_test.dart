import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';
import 'package:teczka_zdrowia/data/koofr_backup.dart';
import 'package:teczka_zdrowia/data/meds.dart';

/// Kontrakt wymiany (WYMIANA.md w repozytorium Rytmu Snu) z perspektywy Teczki.
void main() {
  test('czynniki-leki: zgodne z kontraktem, daty po kolei, bez nazw leków', () {
    final bytes = lekiFactors({
      '2026-11-19': const Adherence(2, 1, 1),
      '2026-11-18': const Adherence(2, 2, 0),
    }, DateTime(2026, 11, 20));
    expect(sprawdzWymiane('czynniki-leki', bytes), isEmpty);
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    expect([for (final d in j['days'] as List) d['date']], ['2026-11-18', '2026-11-19']);
    expect((j['days'] as List).last, {'date': '2026-11-19', 'doses': 2, 'taken': 1, 'missed': 1});
    expect(utf8.decode(bytes), isNot(contains('name')));
  });
}
