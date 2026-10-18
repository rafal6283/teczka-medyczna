# Teczka Zdrowia

Prywatne archiwum wyników badań całej rodziny na Androida i iPhone'a (Flutter). Wszystko działa lokalnie na telefonie – pliki, rozpoznawanie tekstu i analiza nie opuszczają urządzenia.

## Co potrafi

- **Wiele osób** – profil z datą urodzenia, płcią, wzrostem, grupą krwi, alergiami, chorobami i lekami.
- **Dokumenty** – PDF z laboratorium, skan papierowego wyniku aparatem (wykrywanie krawędzi kartki), zdjęcia z galerii albo wpis ręczny. Kategorie, wyszukiwanie również w treści dokumentów, oznaczanie ważnych.
- **Odczyt wyników** – tekst z PDF, a dla skanów OCR (ML Kit) składany w wiersze tabeli; parser rozpoznaje ok. 110 parametrów (morfologia, lipidogram, wątroba, nerki, tarczyca, hormony, witaminy, krzepnięcie, mocz) razem z wartością, jednostką, normą i flagą H/L. Nieznane parametry z jednostką i normą też są wyłapywane. Przed zapisem wszystko można sprawdzić i poprawić.
- **Grafiki ze skanów** – automatyczne wykrywanie wykresów, zdjęć (USG, EKG) na stronach i zapis jako osobne obrazy; ręczne wycinanie fragmentu strony.
- **Analiza w czasie** – wykres z pasmem normy i linią trendu, statystyki (min/maks/średnia, zmiana od poprzedniego i pierwszego, trend roczny, liczba wyników poza normą), przeliczanie jednostek między laboratoriami (np. mmol/l ↔ mg/dl).
- **Podsumowanie** – co jest poza normą (i od ilu wyników z rzędu), co wróciło do normy, co zbliża się do granicy przy obecnym tempie, duże zmiany, dawno niebadane parametry.
- **Pomiary** – masa ciała + BMI, ciśnienie (średnia 30 dni wg ESC), tętno, glukoza z glukometru, temperatura, SpO₂, obwód talii, wzrost.
- **Bezpieczeństwo** – blokada odciskiem/twarzą, kopia zapasowa .zip (też do przeniesienia danych między Androidem a iPhonem).

## Instalacja

Każdy push na `main` buduje aplikację w GitHub Actions i publikuje ją w zakładce **Releases**:

- **Android** – `teczka-zdrowia.apk`: pobierz na telefonie i zainstaluj. Kolejne wersje instalują się jako aktualizacja (stały klucz `android/app/teczka.jks`), dane zostają.
- **iPhone** – `teczka-zdrowia.ipa` (niepodpisany): zainstaluj z komputera przez [Sideloadly](https://sideloadly.io) lub AltStore swoim Apple ID. Przy darmowym koncie aplikację trzeba odświeżać co 7 dni (dane zostają).

## Struktura

- `lib/parse/` – słownik parametrów, parser wyników, odczyt PDF/OCR, wykrywanie grafik
- `lib/analysis/` – serie, statystyki, trendy, wnioski, BMI, ciśnienie
- `lib/data/` – baza SQLite, pliki, kopia zapasowa
- `lib/ui/` – ekrany
- `test/parser_test.dart` – testy parsera na przykładowych wynikach (uruchamiane w CI)

Aplikacja nie jest wyrobem medycznym – rozpoznane wartości zawsze warto porównać z oryginałem.
