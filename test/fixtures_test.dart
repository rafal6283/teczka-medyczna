// Prawdziwe wyniki z Diagnostyki (zanonimizowane), przepuszczone przez OCR – sprawdzamy,
// czy parser wyciąga z nich właściwe wartości. Raport z odczytu trafia do build/fixtures_report.txt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teczka_zdrowia/parse/lab_dictionary.dart';
import 'package:teczka_zdrowia/parse/lab_parser.dart';
import 'package:teczka_zdrowia/parse/text_utils.dart';

/// Oczekiwania: klucz -> liczba (wartość) albo tekst (wynik opisowy).
/// Dodatkowe klucze: '@date', '@title', 'KEY.refLow', 'KEY.refHigh', 'KEY.flag', 'KEY.ref', 'KEY.base'.
const expectations = <String, Map<String, Object>>{
  '2024-03-18_morfologia_mocz_osad': {
    '@date': '2024-03-18',
    'WBC': 6.08, 'RBC': 5.81, 'RBC.base': 5.81, 'HGB': 17.2, 'HCT': 49.6, 'MCV': 85.4, 'PLT': 311, 'PLT.base': 311,
    'NEU': 3.71, 'LYM': 2.0, 'EOS_P': 0.8, 'EOS_P.flag': 'L', 'IG': 0.02, 'NRBC_P': 0, 'RDW': 12.9, 'RDWSD': 40.0, 'PCT': 0.3,
    'U_CLAR': 'mętny', 'U_CLAR.ref': 'przejrzysty', 'U_SG': 1.026, 'U_PH': 5.5, 'U_GLU': 'nie wykryto', 'U_KET': 0,
    'U_UBG': 1, 'U_PROT': 15, 'U_PROT.ref': 'nie wykryto', 'U_LEU_T': 'nie wykryto', 'U_BLOOD': 'nie wykryto', 'U_NIT': 'nie wykryto',
    'U_ERY_S': 3.4, 'U_LEU_S': 3.1, 'U_CAST': 0, 'U_BACT': 3.4, 'U_NAB': 0.6, 'U_NAB_O': 0, 'U_YEAST': 0, 'U_MUC': 'nieobecne', 'U_CRYST': 'liczne',
  },
  '2024-03-18_kreatynina_lipidogram_alt_psa': {
    '@date': '2024-03-18',
    'CREA': 0.97, 'CREA.base': 0.97, 'EGFR': 60, 'EGFR.refLow': 60, 'UA': 4.9, 'GLU': 98.1, 'CHOL': 232.8, 'CHOL.flag': 'H', 'HDL': 41.1,
    'NHDL': 191.7, 'LDL': 153.12, 'TG': 192.9, 'TG.refHigh': 150, 'TG.flag': 'H', 'ALT': 16, 'ALT.refHigh': 41, 'AST': 12, 'GGT': 22, 'PSA': 0.78,
  },
  '2024-03-18_krew_utajona': {'FOBT': 'ujemny'},
  '2024-09-25_morfologia': {'@date': '2024-09-25', 'WBC': 6.4, 'RBC': 5.94, 'LYM_P': 47.7, 'LYM_P.flag': 'H', 'IG_P': 0.5, 'PLT': 273},
  '2024-09-25_bilirubina_alt_crp_tsh': {
    'BIL': 0.56, 'CREA': 0.95, 'EGFR': 90, 'EGFR.refLow': 90, 'ALT': 26, 'AST': 20, 'GGT': 27, 'LIP': 24, 'CRP': 0.6, 'TSH': 1.17, 'TSH.base': 1.17,
  },
  '2025-04-09_glukoza_lipidogram': {'@date': '2025-04-09', 'GLU': 91.5, 'CHOL': 216.2, 'CHOL.flag': 'H', 'HDL': 35.4, 'NHDL': 180.8, 'LDL': 139.7, 'TG': 226.8},
  '2025-04-09_glukoza_lipidogram_morfologia_mocz': {'GLU': 91.5, 'WBC': 6.26, 'HCT.flag': 'H', 'U_GLU': 'nie wykryto', 'U_CLAR': 'przejrzysty'},
  '2025-04-09_morfologia_mocz': {
    'WBC': 6.26, 'NEU': 3.03, 'NEU_P': 48.5, 'RBC': 6.05, 'HCT': 52.8, 'HCT.flag': 'H', 'PLT': 318, 'U_CLAR': 'przejrzysty', 'U_COLOR': 'jasnożółty',
    'U_SG': 1.026, 'U_PROT': 'nie wykryto', 'U_NIT': 'nie wykryto',
  },
  '2025-04-29_lipidogram_alt': {'CHOL': 237.9, 'CHOL.flag': 'H', 'HDL': 38.0, 'LDL': 152.57, 'TG': 256.3, 'ALT': 30},
  '2025-04-30_helicobacter': {'HP_AG': 'dodatni'},
  '2025-05-05_tsh_ft3_ft4': {'TSH': 1.25, 'TSH.base': 1.25, 'FT3': 3.53, 'FT4': 1.51, 'FT4.refHigh': 1.68},
  '2025-12-22_morfologia': {'@date': '2025-12-22', 'WBC': 5.87, 'LYM_P': 45.1, 'LYM_P.flag': 'H', 'PCT': 0.4, 'PCT.flag': 'H', 'RBC': 5.93},
  '2025-12-22_biochemia_ntprobnp_hba1c': {
    'CREA': 0.98, 'EGFR': 90, 'GLU': 90.1, 'CHOL': 220.3, 'HDL': 41.5, 'LDL': 149.48, 'TG': 161.4, 'ALT': 14, 'CK': 69, 'NA': 141, 'K': 4.73,
    'MG': 1.07, 'MG.flag': 'H', 'TSH': 0.796, 'TSH.base': 0.796, 'NTBNP': 195, 'NTBNP.flag': 'H', 'HBA1C_IFCC': 30.8, 'HBA1C': 5.0,
  },
  '2026-08-28_giardia': {'GIARDIA': 'ujemny'},
  '2026-08-28_helicobacter': {'HP_AG': 'ujemny'},
  '2026-08-27_kreatynina_psa': {'CREA': 0.99, 'EGFR': 90, 'EGFR.refLow': 90, 'PSA': 0.878},
  '2026-08-28_anty_ttg': {'@date': '2026-08-27', 'TTG_IGA': 2, 'TTG_IGA.refHigh': 20, 'TTG_IGG': 2},
};

void main() {
  final report = StringBuffer();
  final dir = Directory('test/fixtures');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()..sort((a, b) => a.path.compareTo(b.path));

  tearDownAll(() {
    Directory('build').createSync(recursive: true);
    File('build/fixtures_report.txt').writeAsStringSync(report.toString());
  });

  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceAll('.txt', '');
    test('fixture $name', () {
      final out = LabParser.parse(f.readAsStringSync());
      report.writeln('### $name  date=${out.date} title="${out.suggestedTitle}" cat=${out.suggestedCategory}');
      for (final r in out.results) {
        report.writeln('  ${r.known ? ' ' : '?'} $r   <= ${r.rawLine}');
      }
      final exp = expectations[name] ?? {};
      final errors = <String>[];
      ParsedResult? res(String k) => out.results.where((r) => r.key == k).firstOrNull;
      exp.forEach((k, v) {
        if (k == '@date') {
          final d = out.date;
          final s = d == null ? 'null' : '${d.year}-${two(d.month)}-${two(d.day)}';
          if (s != v) errors.add('data: $s zamiast $v');
          return;
        }
        final parts = k.split('.');
        final r = res(parts[0]);
        if (r == null) {
          errors.add('brak ${parts[0]}');
          return;
        }
        if (parts.length == 1) {
          if (v is String) {
            if (r.valueText != v) errors.add('${parts[0]}: "${r.valueText}" zamiast "$v"');
          } else if (r.value == null || (r.value! - (v as num)).abs() > 1e-6) {
            errors.add('${parts[0]}: ${r.value} zamiast $v');
          }
          return;
        }
        switch (parts[1]) {
          case 'flag':
            if (r.flag != v) errors.add('$k: ${r.flag} zamiast $v');
          case 'ref':
            if (r.refText != v) errors.add('$k: ${r.refText} zamiast $v');
          case 'refLow':
            if (r.refLow != (v as num).toDouble()) errors.add('$k: ${r.refLow} zamiast $v');
          case 'refHigh':
            if (r.refHigh != (v as num).toDouble()) errors.add('$k: ${r.refHigh} zamiast $v');
          case 'base':
            final b = LabDictionary.get(r.key)?.toBase(r.value ?? double.nan, r.unit);
            if (b == null || (b - (v as num)).abs() > 1e-6) errors.add('$k: przeliczenie jednostki "${r.unit}" = $b zamiast $v');
        }
      });
      final unknown = out.results.where((r) => !r.known).toList();
      if (unknown.isNotEmpty) errors.add('nieznane: ${unknown.map((e) => e.rawLine).join(' / ')}');
      if (errors.isNotEmpty) report.writeln('  BŁĘDY: ${errors.join('; ')}');
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  }
}
