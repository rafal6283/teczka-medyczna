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

  test('Diagnostyka (OCR) – morfologia z jednostkami z gwiazdką i flagą na końcu', () {
    const t = """
Data rejestracji: 2025-04-09
Data/godz. pobrania: 2025-04-09 09:00
Data urodzenia: 1983-10-21
Morfologia krwi (ICD-9: C55) 1
Leukocyty   6,26   tys/µl*   4,00 - 10,00
Neutrofile   3,03   tys/pl*   1,90 - 7,00
Limfocyty   2,6   tys/µl*   1,5 - 4,5
Niedojrzałe granulocyty IG   0,02   tys/µl*   0,00 - 0,07
Neutrofile   48,5   %*   45,0 - 70,0
Niedojrzałe granulocyty IG   0,30   %*   0,00 - 1,00
Erytrocyty   6,05   mln/µl*   4,60 - 6,50
Hemoglobina   17,2   g/dl*   13,5 - 18,0
Hematokryt   52,8   %*   40,0 - 52,0   H
MCV   87,3   fl*   80,0 - 98,0
RDW-SD   43,8   fl*   36,0 - 47,0
RDW-CV   13,6   %*   11,5 - 14,5
NRBC   0,00   tys/µl*   0,00 - 0,01
NRBC   0,00   %*   0,00 - 0,20
Płytki krwi   318   tys/µl*   150 - 400
PCT   0,3   %*   0,1 - 0,4
P-LCR   25,3   %*   19,3 - 47,1
Glukoza (ICD-9: L43) 1   91,5   mg/dl   70,0 - 99,0
prawidłowa glikemia na czczo: 70-99 mg/dl
cukrzyca ≥ 200 mg/dl, wynik uzyskany w próbce pobranej o dowolnej porze dnia
Cholesterol całkowity   216,20   mg/dl   115,00 - 190,00   H
Cholesterol HDL   35,40   mg/dl   -
Stężenie zalecane: powyżej 40 mg/dl
Poniżej 130 mg/dl - dla osób z umiarkowanym ryzykiem sercowo-naczyniowym
Cholesterol LDL   139,70   mg/dl   -
Cholesterol LDL wyliczony ze wzoru Sampson-NIH
Triglicerydy   226,80   mg/dl   -
""";
    final out = LabParser.parse(t);
    final r = out.results;
    expect(out.date, DateTime(2025, 4, 9));
    expect(find(r, 'WBC')!.value, 6.26);
    expect(find(r, 'WBC')!.refHigh, 10);
    expect(find(r, 'NEU')!.value, 3.03);
    expect(LabDictionary.get('NEU')!.toBase(3.03, find(r, 'NEU')!.unit), 3.03);
    expect(find(r, 'NEU_P')!.value, 48.5);
    expect(find(r, 'IG')!.value, 0.02);
    expect(find(r, 'IG_P')!.value, 0.30);
    expect(find(r, 'RBC')!.value, 6.05);
    expect(find(r, 'HGB')!.value, 17.2);
    expect(find(r, 'HCT')!.flag, 'H');
    expect(find(r, 'HCT')!.refHigh, 52);
    expect(find(r, 'RDWSD')!.value, 43.8);
    expect(find(r, 'RDW')!.value, 13.6);
    expect(find(r, 'NRBC')!.value, 0);
    expect(find(r, 'NRBC_P')!.refHigh, 0.2);
    expect(find(r, 'PLT')!.value, 318);
    expect(find(r, 'PCT')!.value, 0.3);
    expect(find(r, 'PLCR')!.value, 25.3);
    expect(find(r, 'GLU')!.value, 91.5);
    expect(find(r, 'GLU')!.refLow, 70);
    expect(find(r, 'CHOL')!.flag, 'H');
    expect(find(r, 'HDL')!.value, 35.4);
    expect(find(r, 'LDL')!.value, 139.7);
    expect(find(r, 'TG')!.value, 226.8);
    expect(r.where((x) => !x.known), isEmpty, reason: r.where((x) => !x.known).map((e) => e.rawLine).join(' / '));
  });
}
