import 'package:flutter_test/flutter_test.dart';
import 'package:teczka_zdrowia/parse/lab_dictionary.dart';

/// Normy ze słownika zależne od wieku i płci (używane, gdy wynik nie podaje własnej normy).
void main() {
  test('wiek w dniu badania', () {
    expect(ageAt(DateTime(1980, 1, 1), DateTime(2025, 12, 22)), 45);
    expect(ageAt(DateTime(1980, 12, 23), DateTime(2025, 12, 22)), 44); // dzień przed urodzinami
    expect(ageAt(null, DateTime(2025, 1, 1)), isNull);
  });

  test('PSA: górna granica rośnie z wiekiem', () {
    final psa = LabDictionary.get('PSA')!;
    expect(psa.highFor('M'), 4.0); // bez wieku — jak dotąd
    expect(psa.highFor('M', age: 45), 2.5);
    expect(psa.highFor('M', age: 55), 3.5);
    expect(psa.highFor('M', age: 65), 4.5);
    expect(psa.highFor('M', age: 82), 6.5);
    expect(psa.highFor('M', age: 30), 4.0);
  });

  test('OB: po 50. roku życia wiek/2 u mężczyzn i (wiek+10)/2 u kobiet', () {
    final ob = LabDictionary.get('OB')!;
    expect(ob.highFor('M', age: 40), 15.0);
    expect(ob.highFor('M', age: 70), 35.0);
    expect(ob.highFor('K', age: 70), 40.0);
    expect(ob.highFor('K', age: 52), 31.0);
    expect(ob.highFor(null, age: 70), 15.0); // płeć nieznana — zwykła norma
  });

  test('D-dimery: próg zależny od wieku po 50. roku życia', () {
    final dd = LabDictionary.get('DDIM')!;
    expect(dd.highFor('M', age: 45), 500.0);
    expect(dd.highFor('M', age: 72), 720.0);
    expect(dd.highFor(null), 500.0);
  });
}
