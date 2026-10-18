import 'package:flutter_test/flutter_test.dart';
import 'package:teczka_zdrowia/parse/lab_parser.dart';
import 'package:teczka_zdrowia/parse/report_parser.dart';

const kolonoskopia = '''
Pracownia Endoskopii
Pacjent: Jan Kowalski   PESEL: 80010112345
Data badania: 14.05.2024
KOLONOSKOPIA
Opis badania:
Kolonoskop wprowadzono do kątnicy. Przygotowanie jelita dobre (BBPS 8).
W esicy polip uszypułowany 6 mm, usunięty pętlą w całości, pobrano do badania hp.
Nie stwierdzono uchyłków. Błona śluzowa odbytnicy bez zmian zapalnych.
Guzki krwawnicze II stopnia.
Wnioski:
Polip esicy – polipektomia. Hemoroidy II st.
Zalecenia:
Oczekiwać na wynik histopatologiczny. Kontrolna kolonoskopia za 3 lata.
Lekarz wykonujący: dr n. med. A. Nowak
''';

const holter = '''
BADANIE HOLTEROWSKIE EKG
Data rejestracji 02.10.2025
Czas rejestracji 23 h 51 min
Średnia częstość rytmu 74 /min
Minimalna częstość rytmu 48 /min
Maksymalna częstość rytmu 138 /min
Pobudzenia nadkomorowe: 312
Pobudzenia komorowe: 1250
Pauzy > 2 s: 0
Wnioski:
Rytm zatokowy. Pojedyncze pobudzenia nadkomorowe. Liczne pojedyncze pobudzenia komorowe, 3 pary.
Nie zarejestrowano pauz ani zaburzeń przewodzenia. Nie stwierdzono migotania przedsionków.
Zalecenia: kontrola kardiologiczna za 6 miesięcy.
''';

void main() {
  test('Kolonoskopia: rodzaj, sekcje, istotne zapisy z zaprzeczeniami, kontrola', () {
    final r = ReportParser.parse(kolonoskopia, docDate: DateTime(2024, 5, 14));
    expect(r.examType, 'COLONO');
    expect(r.conclusions, contains('Polip esicy'));
    expect(r.recommendations, contains('za 3 lata'));
    expect(r.description, contains('kątnicy'));
    final abn = r.abnormal.map((f) => f.sentence).join(' | ');
    expect(abn, contains('polip uszypułowany'));
    expect(abn, contains('Guzki krwawnicze'));
    expect(abn, isNot(contains('uchyłków')), reason: 'zaprzeczone: nie stwierdzono uchyłków');
    expect(abn, isNot(contains('odbytnicy bez zmian')), reason: 'zaprzeczone: bez zmian zapalnych');
    expect(r.followUp, isNotNull);
    expect(r.followUp!.year, 2027);
  });

  test('Holter: liczby jako parametry, wnioski, kontrola za 6 miesięcy', () {
    final r = ReportParser.parse(holter, docDate: DateTime(2025, 10, 2));
    expect(r.examType, 'HOLTER_EKG');
    expect(r.conclusions, contains('Rytm zatokowy'));
    final abn = r.abnormal.map((f) => f.sentence).join(' | ');
    expect(abn, contains('pobudzenia komorowe'));
    expect(abn, isNot(contains('migotania')));
    expect(r.followUp!.month, 4);
    expect(r.followUp!.year, 2026);

    final p = LabParser.parse(holter).results;
    double? v(String k) => p.where((x) => x.key == k).firstOrNull?.value;
    expect(v('HR_AVG'), 74);
    expect(v('HR_MIN'), 48);
    expect(v('HR_MAX'), 138);
    expect(v('SVE'), 312);
    expect(v('VE'), 1250);
    expect(v('PAUSE'), 0);
  });

  test('Zapis i odczyt JSON', () {
    final r = ReportParser.parse(kolonoskopia, docDate: DateTime(2024, 5, 14));
    final back = DoctorReport.fromJson(r.toJson())!;
    expect(back.examType, 'COLONO');
    expect(back.abnormal.length, r.abnormal.length);
    expect(back.followUp, r.followUp);
  });
}
