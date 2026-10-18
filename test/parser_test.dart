import 'package:flutter_test/flutter_test.dart';
import 'package:teczka_zdrowia/parse/lab_parser.dart';
import 'package:teczka_zdrowia/parse/lab_dictionary.dart';

const diagnostyka = '''
Diagnostyka Sp. z o.o. Laboratorium Medyczne
Pacjent: JAN KOWALSKI   PESEL: 80010112345
Data urodzenia: 01.01.1980
Data pobrania materiału: 12.03.2025 07:45
Data wydruku: 13.03.2025
C55 Morfologia krwi
WBC - leukocyty 6,52 tys/µl 4,00 - 10,00
RBC - erytrocyty 4,85 mln/µl 4,50 - 5,90
Hemoglobina 14,8 g/dl 13,5 - 17,5
Hematokryt 43,1 % 40,0 - 52,0
MCV 88,9 fl 80,0 - 99,0
PLT - płytki krwi 245 tys/µl 150 - 410
Neutrofile 3,41 tys/µl 1,80 - 7,70
Neutrofile % 52,3 % 40,0 - 70,0
Limfocyty 2,31 tys/µl 1,00 - 4,50
I81 Lipidogram
Cholesterol całkowity 215 H mg/dl < 190
Cholesterol HDL 52 mg/dl > 40
Cholesterol LDL wyliczany 138 H mg/dl < 115
Cholesterol nie-HDL 163 mg/dl < 130
Triglicerydy 125 mg/dl < 150
L43 TSH trzeciej generacji 1,872 µIU/ml 0,270 - 4,200
Glukoza 5,4 mmol/l 3,9 - 5,5
Witamina D3 metabolit 25(OH) 24,6 ↓ ng/ml 30,0 - 50,0
eGFR wg CKD-EPI >90 ml/min/1,73m2 > 60
Na podstawie badania 12 pacjent skierowany.
''';

const alab = '''
ALAB laboratoria
Data rejestracji: 2024-11-05
Badanie            Wynik     Jednostka    Zakres referencyjny
Leukocyty (WBC)    7.1       10^9/L       4.0-10.0
Hemoglobina        8.9       mmol/l       7.5 - 10.0
ALT (AlAT)         45   H    U/l          < 41
AST (AspAT)        28        U/l          do 40
Kreatynina         0,92      mg/dl        0,70 - 1,20
Ferrytyna          18        ng/ml        30 - 400
CRP
3,2 mg/l < 5,0
Potas              4,4       mmol/l       3,5 - 5,1
''';

ParsedResult? find(List<ParsedResult> r, String key) {
  for (final x in r) {
    if (x.key == key) return x;
  }
  return null;
}

void main() {
  test('Diagnostyka – typowy układ wierszy', () {
    final out = LabParser.parse(diagnostyka);
    final r = out.results;
    expect(out.date, DateTime(2025, 3, 12));
    expect(out.facility, 'Diagnostyka');

    final wbc = find(r, 'WBC')!;
    expect(wbc.value, 6.52);
    expect(wbc.unit, 'tys/µl');
    expect(wbc.refLow, 4.0);
    expect(wbc.refHigh, 10.0);

    expect(find(r, 'HGB')!.value, 14.8);
    expect(find(r, 'HCT')!.unit, '%');
    expect(find(r, 'PLT')!.value, 245);
    expect(find(r, 'NEU')!.value, 3.41);
    expect(find(r, 'NEU_P')!.value, 52.3);

    final chol = find(r, 'CHOL')!;
    expect(chol.value, 215);
    expect(chol.flag, 'H');
    expect(chol.refHigh, 190);
    expect(chol.refLow, null);

    expect(find(r, 'HDL')!.refLow, 40);
    expect(find(r, 'LDL')!.value, 138);
    expect(find(r, 'NHDL')!.value, 163);
    expect(find(r, 'TSH')!.value, 1.872);
    expect(find(r, 'GLU')!.unit, 'mmol/l');

    final d = find(r, 'VITD')!;
    expect(d.value, 24.6);
    expect(d.flag, 'L');
    expect(d.unit, 'ng/ml');

    final egfr = find(r, 'EGFR')!;
    expect(egfr.valueText, '>90');
    expect(egfr.refLow, 60);

    expect(find(r, 'NA'), isNull, reason: 'zdanie zaczynające się od "Na" to nie sód');
  });

  test('ALAB – kolumny, jednostki SI i wartość w kolejnej linii', () {
    final out = LabParser.parse(alab);
    final r = out.results;
    expect(out.date, DateTime(2024, 11, 5));
    expect(out.facility, 'ALAB laboratoria');
    expect(find(r, 'WBC')!.value, 7.1);
    expect(find(r, 'WBC')!.unit, '10^9/L');
    final hgb = find(r, 'HGB')!;
    expect(hgb.value, 8.9);
    expect(LabDictionary.get('HGB')!.toBase(hgb.value!, hgb.unit)!, closeTo(14.34, 0.05));
    final alt = find(r, 'ALT')!;
    expect(alt.flag, 'H');
    expect(alt.refHigh, 41);
    expect(find(r, 'AST')!.refHigh, 40);
    expect(find(r, 'FERR')!.refLow, 30);
    expect(find(r, 'CRP')!.value, 3.2);
    expect(find(r, 'K')!.value, 4.4);
  });

  test('Nieznany parametr z jednostką i normą', () {
    final out = LabParser.parse('Cynk 82 µg/dl 70 - 120\nWiek 45 lat');
    expect(out.results.length, 1);
    expect(out.results.first.known, false);
    expect(out.results.first.name, 'Cynk');
    expect(out.results.first.refHigh, 120);
  });

  test('Tekst z OCR – u zamiast µ, µmol/l, przecinki i flagi', () {
    const t = """
Data pobrania 03.02.2023
Hemoglobina   14,2 g/dL   12,0-16,0
TSH 2,15 uIU/ml 0,27 - 4,20
Kreatynina 78 umol/l 62-106
Glukoza 112 * mg/dl 70 - 99
Cholesterol całkowity 6,1 mmol/l <5,0
""";
    final out = LabParser.parse(t);
    final r = out.results;
    expect(out.date, DateTime(2023, 2, 3));
    expect(find(r, 'HGB')!.value, 14.2);
    expect(find(r, 'TSH')!.unit, 'uIU/ml');
    final crea = find(r, 'CREA')!;
    expect(LabDictionary.get('CREA')!.toBase(crea.value!, crea.unit)!, closeTo(0.88, 0.01));
    expect(find(r, 'GLU')!.value, 112);
    expect(find(r, 'GLU')!.refHigh, 99);
    final chol = find(r, 'CHOL')!;
    expect(chol.refHigh, 5.0);
    expect(LabDictionary.get('CHOL')!.toBase(chol.value!, chol.unit)!, closeTo(235.9, 0.5));
  });
}
