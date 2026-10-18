// Słownik najczęstszych parametrów badań w polskich wynikach laboratoryjnych.
// Zakresy są orientacyjne – używane tylko wtedy, gdy wynik nie podaje własnej normy.

import 'text_utils.dart';

class LabParam {
  final String key;
  final String name;
  final String category;
  final String unit;
  final double? low, high;
  double? mLow, mHigh, fLow, fHigh;
  final List<String> aliases = [];

  /// Klucz wariantu procentowego (np. neutrofile % obok bezwzględnych).
  String? pctKey;

  /// wartość w jednostce X * mnożnik = wartość w jednostce podstawowej
  final Map<String, double> conv = {};

  LabParam(this.key, this.name, this.category, this.unit, this.low, this.high);

  LabParam a(List<String> al) {
    for (final s in al) {
      final n = normText(s);
      aliases.add(n);
      // "P/c. anty-tTG", "Przeciwciała anty-…" – ten sam parametr
      if (n.startsWith('anty ')) {
        aliases.add('p c $n');
        aliases.add('pc $n');
        aliases.add('przeciwciala $n');
        aliases.add('p c p $n');
      }
    }
    return this;
  }

  LabParam m(double? l, double? h) {
    mLow = l;
    mHigh = h;
    return this;
  }

  LabParam f(double? l, double? h) {
    fLow = l;
    fHigh = h;
    return this;
  }

  LabParam pct(String k) {
    pctKey = k;
    return this;
  }

  LabParam c(String u, double factor) {
    conv[normUnit(u)] = factor;
    return this;
  }

  bool _hasM() => mLow != null || mHigh != null;
  bool _hasF() => fLow != null || fHigh != null;

  double? lowFor(String? sex) {
    if (sex == 'M' && _hasM()) return mLow;
    if (sex == 'K' && _hasF()) return fLow;
    return low;
  }

  double? highFor(String? sex) {
    if (sex == 'M' && _hasM()) return mHigh;
    if (sex == 'K' && _hasF()) return fHigh;
    return high;
  }

  /// Przelicza na jednostkę podstawową; null gdy nie wiadomo jak.
  double? toBase(double v, String? fromUnit) {
    final u = normUnit(fromUnit ?? '');
    if (u.isEmpty || u == normUnit(unit)) return v;
    final f = conv[u];
    return f == null ? null : v * f;
  }
}

class LabDictionary {
  static const morf = 'Morfologia';
  static const bio = 'Biochemia';
  static const lip = 'Lipidogram';
  static const wat = 'Wątroba i trzustka';
  static const ner = 'Nerki i elektrolity';
  static const tar = 'Tarczyca';
  static const hor = 'Hormony';
  static const zel = 'Żelazo i witaminy';
  static const zap = 'Stan zapalny';
  static const krz = 'Krzepnięcie';
  static const moc = 'Mocz';
  static const ekg = 'EKG i Holter';
  static const imm = 'Immunologia i serologia';
  static const kal = 'Kał';
  static const serce = 'Serce';
  static const onko = 'Markery nowotworowe';
  static const inf = 'Infekcje';
  static const gaz = 'Gazometria';
  static const leki = 'Leki (stężenia)';
  static const eye = 'Wzrok';
  static const inne = 'Inne';

  static const categoryOrder = [morf, bio, lip, wat, ner, tar, hor, zel, zap, imm, inf, onko, serce, krz, gaz, moc, kal, ekg, eye, leki, inne];

  static final Map<String, LabParam> byKey = {};

  /// (alias, parametr) od najdłuższego aliasu.
  static final List<MapEntry<String, LabParam>> aliases = [];

  /// Nazwy obowiązujące tylko w sekcji badania ogólnego moczu / osadu moczu.
  static final List<MapEntry<String, LabParam>> urineAliases = [];
  static final List<MapEntry<String, LabParam>> sedimentAliases = [];

  static bool _ready = false;

  static LabParam _p(String key, String name, String cat, String unit, double? low, double? high) {
    final x = LabParam(key, name, cat, unit, low, high);
    byKey[key] = x;
    return x;
  }

  static LabParam? get(String key) {
    ensure();
    return byKey[key];
  }

  static List<LabParam> all() {
    ensure();
    return byKey.values.toList();
  }

  static LabParam resolve(LabParam base, bool percent) {
    if (percent && base.pctKey != null) return byKey[base.pctKey!] ?? base;
    return base;
  }

  static LabParam? findByName(String name) {
    ensure();
    final n = normText(name);
    for (final a in aliases) {
      if (a.key == n) return a.value;
    }
    for (final x in byKey.values) {
      if (normText(x.name) == n) return x;
    }
    return null;
  }

  static void ensure() {
    if (_ready) return;
    _ready = true;
    const cell = ['10^9/l', 'g/l', '10^3/ul', 'k/ul', 'tys/ul', 'tys./ul'];
    LabParam cells(LabParam p) {
      for (final u in cell) {
        p.c(u, 1);
      }
      return p;
    }

    LabParam enz(LabParam p) => p.c('iu/l', 1).c('j/l', 1).c('u/l', 1);

    // ---------- Morfologia ----------
    cells(_p('WBC', 'Leukocyty (WBC)', morf, 'tys/µl', 4.0, 10.0)
        .a(['leukocyty', 'wbc', 'krwinki białe', 'białe krwinki', 'leukocyty wbc', 'wbc leukocyty', 'krwinki białe wbc']));
    _p('RBC', 'Erytrocyty (RBC)', morf, 'mln/µl', 4.2, 5.4)
        .m(4.5, 5.9)
        .f(4.0, 5.2)
        .a(['erytrocyty', 'rbc', 'krwinki czerwone', 'czerwone krwinki', 'erytrocyty rbc', 'rbc erytrocyty', 'krwinki czerwone rbc'])
        .c('10^12/l', 1)
        .c('t/l', 1)
        .c('10^6/ul', 1)
        .c('m/ul', 1)
        .c('mln/ul', 1);
    _p('HGB', 'Hemoglobina (HGB)', morf, 'g/dl', 12.0, 16.0)
        .m(13.5, 17.5)
        .f(12.0, 15.5)
        .a(['hemoglobina', 'hgb', 'hb', 'hemoglobina hgb', 'hgb hemoglobina'])
        .c('g/l', 0.1)
        .c('mmol/l', 1.611);
    _p('HCT', 'Hematokryt (HCT)', morf, '%', 37.0, 47.0)
        .m(40.0, 52.0)
        .f(36.0, 46.0)
        .a(['hematokryt', 'hct', 'hematokryt hct', 'hct hematokryt'])
        .c('l/l', 100);
    _p('MCV', 'MCV', morf, 'fl', 80.0, 100.0).a(['mcv', 'średnia objętość krwinki', 'średnia objętość krwinki czerwonej', 'średnia objętość erytrocytu', 'mcv średnia objętość krwinki czerwonej']);
    _p('MCH', 'MCH', morf, 'pg', 27.0, 34.0).a(['mch', 'średnia masa hemoglobiny w krwince', 'średnia zawartość hemoglobiny w erytrocycie', 'średnia masa hemoglobiny w krwince czerwonej']);
    _p('MCHC', 'MCHC', morf, 'g/dl', 32.0, 36.0)
        .a(['mchc', 'średnie stężenie hemoglobiny w krwince', 'średnie stężenie hemoglobiny w krwince czerwonej'])
        .c('g/l', 0.1)
        .c('mmol/l', 1.611);
    _p('RDW', 'RDW-CV', morf, '%', 11.5, 14.5).a(['rdw', 'rdw cv', 'wskaźnik anizocytozy', 'rozkład objętości erytrocytów']);
    _p('RDWSD', 'RDW-SD', morf, 'fl', 37.0, 54.0).a(['rdw sd']);
    cells(_p('PLT', 'Płytki krwi (PLT)', morf, 'tys/µl', 150.0, 400.0)
        .a(['płytki krwi', 'płytki', 'plt', 'trombocyty', 'płytki krwi plt', 'plt płytki krwi', 'trombocyty plt', 'plt trombocyty']));
    _p('MPV', 'MPV', morf, 'fl', 7.5, 11.5).a(['mpv', 'średnia objętość płytki', 'średnia objętość płytek krwi']);
    _p('PDW', 'PDW', morf, 'fl', 9.0, 17.0).a(['pdw', 'wskaźnik zmienności objętości płytek']);
    _p('PCT', 'Płytkokryt (PCT)', morf, '%', 0.15, 0.40).a(['pct', 'płytkokryt', 'plateletkryt', 'płytkokryt pct']);
    _p('PLCR', 'P-LCR', morf, '%', 13.0, 43.0).a(['p lcr', 'plcr']);
    cells(_p('NEU', 'Neutrofile', morf, 'tys/µl', 1.8, 7.7)
        .pct('NEU_P')
        .a(['neutrofile', 'neu', 'neut', 'neutrocyty', 'granulocyty obojętnochłonne', 'neutrofile neu', 'neu neutrofile', 'neutrofile segmentowane']));
    _p('NEU_P', 'Neutrofile %', morf, '%', 40.0, 70.0);
    cells(_p('LYM', 'Limfocyty', morf, 'tys/µl', 1.0, 4.5).pct('LYM_P').a(['limfocyty', 'lym', 'lymph', 'limfocyty lym', 'lym limfocyty', 'limfocyty lymph']));
    _p('LYM_P', 'Limfocyty %', morf, '%', 20.0, 45.0);
    cells(_p('MON', 'Monocyty', morf, 'tys/µl', 0.1, 0.8).pct('MON_P').a(['monocyty', 'mon', 'mono', 'monocyty mono', 'mono monocyty', 'monocyty mon']));
    _p('MON_P', 'Monocyty %', morf, '%', 2.0, 10.0);
    cells(_p('EOS', 'Eozynofile', morf, 'tys/µl', 0.0, 0.5)
        .pct('EOS_P')
        .a(['eozynofile', 'eos', 'eozynocyty', 'granulocyty kwasochłonne', 'eozynofile eos', 'eos eozynofile']));
    _p('EOS_P', 'Eozynofile %', morf, '%', 0.0, 5.0);
    cells(_p('BAS', 'Bazofile', morf, 'tys/µl', 0.0, 0.2)
        .pct('BAS_P')
        .a(['bazofile', 'baso', 'bas', 'bazocyty', 'granulocyty zasadochłonne', 'bazofile baso', 'baso bazofile', 'bazofile bas']));
    _p('BAS_P', 'Bazofile %', morf, '%', 0.0, 1.0);
    cells(_p('IG', 'Niedojrzałe granulocyty (IG)', morf, 'tys/µl', 0.0, 0.06).pct('IG_P').a(['niedojrzałe granulocyty', 'ig', 'ig niedojrzałe granulocyty', 'niedojrzałe granulocyty ig']));
    _p('IG_P', 'Niedojrzałe granulocyty %', morf, '%', 0.0, 0.6);
    cells(_p('NRBC', 'NRBC', morf, 'tys/µl', 0.0, 0.01).pct('NRBC_P').a(['nrbc', 'erytroblasty', 'nrbc erytroblasty']));
    _p('NRBC_P', 'NRBC %', morf, '%', 0.0, 0.2);
    _p('RET', 'Retikulocyty', morf, '‰', 5.0, 15.0).a(['retikulocyty', 'ret']);

    // ---------- Biochemia ----------
    _p('GLU', 'Glukoza', bio, 'mg/dl', 70.0, 99.0)
        .a(['glukoza', 'glukoza na czczo', 'glukoza w surowicy', 'glukoza surowica', 'glu', 'glukoza w osoczu', 'glukoza osocze', 'glukoza w surowicy na czczo'])
        .c('mmol/l', 18.016);
    _p('HBA1C', 'Hemoglobina glikowana (HbA1c)', bio, '%', 4.0, 5.6)
        .a(['hemoglobina glikowana', 'hba1c', 'hb a1c', 'hemoglobina glikowana hba1c', 'hba1c hemoglobina glikowana', 'hemoglobina glikowana hb a1c']);
    _p('INS', 'Insulina', bio, 'µIU/ml', 2.6, 24.9).a(['insulina', 'insulina na czczo']).c('mu/l', 1).c('miu/l', 1).c('uu/ml', 1).c('pmol/l', 0.144);
    _p('HOMA', 'HOMA-IR', bio, '', null, 2.0).a(['homa ir', 'wskaźnik homa ir', 'homa']);
    _p('TP', 'Białko całkowite', bio, 'g/dl', 6.4, 8.3).a(['białko całkowite', 'białko całkowite w surowicy']).c('g/l', 0.1);
    _p('ALB', 'Albumina', bio, 'g/dl', 3.5, 5.2).a(['albumina', 'albuminy', 'albumina w surowicy']).c('g/l', 0.1);
    _p('UA', 'Kwas moczowy', bio, 'mg/dl', 2.6, 7.0).m(3.4, 7.0).f(2.4, 5.7).a(['kwas moczowy', 'kwas moczowy w surowicy']).c('umol/l', 0.01681);
    enz(_p('CK', 'Kinaza kreatynowa (CK)', bio, 'U/l', null, 190.0).a(['kinaza kreatynowa', 'ck', 'cpk', 'kinaza kreatynowa ck', 'kinaza fosfokreatynowa', 'kinaza fosfokreatynowa ck']));
    enz(_p('LDH', 'LDH', bio, 'U/l', 135.0, 225.0).a(['ldh', 'dehydrogenaza mleczanowa', 'dehydrogenaza mleczanowa ldh']));
    _p('HCY', 'Homocysteina', bio, 'µmol/l', 5.0, 15.0).a(['homocysteina']);

    // ---------- Lipidogram ----------
    _p('CHOL', 'Cholesterol całkowity', lip, 'mg/dl', null, 190.0)
        .a(['cholesterol całkowity', 'cholesterol', 'cholesterol całkowity w surowicy', 'chol', 'cholesterol całk', 'cholesterol w surowicy'])
        .c('mmol/l', 38.67);
    _p('HDL', 'Cholesterol HDL', lip, 'mg/dl', 40.0, null)
        .m(40.0, null)
        .f(45.0, null)
        .a(['cholesterol hdl', 'hdl', 'hdl cholesterol', 'cholesterol frakcji hdl', 'cholesterol hdl w surowicy'])
        .c('mmol/l', 38.67);
    _p('LDL', 'Cholesterol LDL', lip, 'mg/dl', null, 115.0)
        .a([
          'cholesterol ldl',
          'ldl',
          'ldl cholesterol',
          'cholesterol ldl wyliczany',
          'cholesterol ldl wyliczony',
          'cholesterol ldl oznaczany bezpośrednio',
          'cholesterol ldl metodą bezpośrednią',
          'cholesterol frakcji ldl',
          'ldl wyliczany',
          'cholesterol ldl w surowicy'
        ])
        .c('mmol/l', 38.67);
    _p('NHDL', 'Cholesterol nie-HDL', lip, 'mg/dl', null, 130.0)
        .a(['cholesterol nie hdl', 'nie hdl cholesterol', 'non hdl', 'cholesterol non hdl', 'non hdl cholesterol'])
        .c('mmol/l', 38.67);
    _p('TG', 'Triglicerydy', lip, 'mg/dl', null, 150.0)
        .a(['triglicerydy', 'trójglicerydy', 'tg', 'triacyloglicerole', 'triglicerydy tg', 'triglicerydy w surowicy'])
        .c('mmol/l', 88.57);
    _p('LPA', 'Lipoproteina (a)', lip, 'mg/dl', null, 30.0).a(['lipoproteina a', 'lp a', 'lpa']);

    // ---------- Wątroba / trzustka ----------
    enz(_p('ALT', 'ALT (AlAT)', wat, 'U/l', null, 40.0)
        .m(null, 41.0)
        .f(null, 33.0)
        .a(['alt', 'alat', 'aminotransferaza alaninowa', 'alt alat', 'alat alt', 'aminotransferaza alaninowa alt', 'aminotransferaza alaninowa alat']));
    enz(_p('AST', 'AST (AspAT)', wat, 'U/l', null, 40.0)
        .m(null, 40.0)
        .f(null, 32.0)
        .a(['ast', 'aspat', 'aminotransferaza asparaginianowa', 'ast aspat', 'aspat ast', 'aminotransferaza asparaginianowa ast', 'aminotransferaza asparaginianowa aspat']));
    enz(_p('GGT', 'GGTP', wat, 'U/l', null, 50.0)
        .m(null, 60.0)
        .f(null, 40.0)
        .a(['ggtp', 'ggt', 'gamma glutamylotranspeptydaza', 'gamma gt', 'ggtp gamma glutamylotranspeptydaza', 'gamma glutamylotransferaza']));
    enz(_p('ALP', 'Fosfataza alkaliczna (ALP)', wat, 'U/l', 40.0, 130.0)
        .f(35.0, 105.0)
        .a(['fosfataza alkaliczna', 'alp', 'fosfataza zasadowa', 'fosfataza alkaliczna alp', 'alp fosfataza alkaliczna']));
    _p('BIL', 'Bilirubina całkowita', wat, 'mg/dl', 0.3, 1.2).a(['bilirubina całkowita', 'bilirubina', 'bilirubina całk', 'bil', 'bilirubina całkowita w surowicy']).c('umol/l', 0.0585);
    _p('BILD', 'Bilirubina bezpośrednia', wat, 'mg/dl', null, 0.3).a(['bilirubina bezpośrednia', 'bilirubina sprzężona']).c('umol/l', 0.0585);
    enz(_p('AMY', 'Amylaza', wat, 'U/l', 28.0, 100.0).a(['amylaza', 'alfa amylaza', 'amylaza w surowicy']));
    enz(_p('LIP', 'Lipaza', wat, 'U/l', 13.0, 60.0).a(['lipaza', 'lipaza w surowicy']));

    // ---------- Nerki / elektrolity ----------
    _p('CREA', 'Kreatynina', ner, 'mg/dl', 0.6, 1.2)
        .m(0.7, 1.2)
        .f(0.5, 0.9)
        .a(['kreatynina', 'kreatynina w surowicy', 'crea', 'kreatynina surowica'])
        .c('umol/l', 0.01131);
    _p('EGFR', 'eGFR', ner, 'ml/min/1,73m²', 90.0, null).a([
      'egfr',
      'gfr',
      'egfr wg ckd epi',
      'egfr ckd epi',
      'szacunkowy gfr',
      'egfr mdrd',
      'przesączanie kłębuszkowe egfr',
      'egfr wg wzoru ckd epi',
      'szacowany wskaźnik filtracji kłębuszkowej'
    ]);
    _p('UREA', 'Mocznik', ner, 'mg/dl', 17.0, 43.0).a(['mocznik', 'mocznik w surowicy']).c('mmol/l', 6.006);
    _p('BUN', 'Azot mocznikowy (BUN)', ner, 'mg/dl', 8.0, 23.0).a(['azot mocznikowy', 'bun']);
    _p('NA', 'Sód', ner, 'mmol/l', 136.0, 145.0).a(['sód', 'na', 'sód na', 'na sód', 'sód w surowicy']).c('meq/l', 1);
    _p('K', 'Potas', ner, 'mmol/l', 3.5, 5.1).a(['potas', 'k', 'potas k', 'k potas', 'potas w surowicy']).c('meq/l', 1);
    _p('CL', 'Chlorki', ner, 'mmol/l', 98.0, 107.0).a(['chlorki', 'cl', 'chlorki cl', 'chlorki w surowicy']).c('meq/l', 1);
    _p('CA', 'Wapń całkowity', ner, 'mg/dl', 8.6, 10.2).a(['wapń', 'wapń całkowity', 'ca', 'wapń całkowity w surowicy', 'wapń w surowicy']).c('mmol/l', 4.008);
    _p('MG', 'Magnez', ner, 'mg/dl', 1.6, 2.6).a(['magnez', 'mg', 'magnez w surowicy']).c('mmol/l', 2.431);
    _p('P', 'Fosfor nieorganiczny', ner, 'mg/dl', 2.5, 4.5).a(['fosfor', 'fosfor nieorganiczny', 'fosforany']).c('mmol/l', 3.097);

    // ---------- Tarczyca ----------
    _p('TSH', 'TSH', tar, 'µIU/ml', 0.27, 4.2)
        .a(['tsh', 'tsh trzeciej generacji', 'tsh iii generacji', 'tsh 3 generacji', 'tyreotropina', 'hormon tyreotropowy', 'tsh 3 gen', 'tsh iii gen', 'tsh ultraczułe'])
        .c('miu/l', 1)
        .c('mu/l', 1)
        .c('uu/ml', 1)
        .c('uiu/ml', 1)
        .c('miu/ml', 1);
    _p('FT4', 'FT4', tar, 'ng/dl', 0.93, 1.7).a(['ft4', 'wolna tyroksyna', 'ft4 wolna tyroksyna', 'wolna tyroksyna ft4']).c('pmol/l', 0.0777);
    _p('FT3', 'FT3', tar, 'pg/ml', 2.0, 4.4).a(['ft3', 'wolna trójjodotyronina', 'ft3 wolna trójjodotyronina', 'wolna trijodotyronina', 'wolna trójjodotyronina ft3']).c('pmol/l', 0.651);
    _p('ATPO', 'Anty-TPO', tar, 'IU/ml', null, 34.0)
        .a(['anty tpo', 'atpo', 'przeciwciała anty tpo', 'przeciwciała przeciw peroksydazie tarczycowej', 'anti tpo', 'przeciwciała anty tpo atpo'])
        .c('u/ml', 1)
        .c('j/ml', 1);
    _p('ATG', 'Anty-TG', tar, 'IU/ml', null, 115.0)
        .a(['anty tg', 'atg', 'przeciwciała anty tg', 'przeciwciała przeciw tyreoglobulinie', 'anti tg', 'przeciwciała anty tg atg'])
        .c('u/ml', 1)
        .c('j/ml', 1);
    _p('TRAB', 'TRAb', tar, 'IU/l', null, 1.75).a(['trab', 'przeciwciała anty trsh', 'anty trsh']);

    // ---------- Hormony ----------
    _p('CORT', 'Kortyzol', hor, 'µg/dl', 6.2, 19.4).a(['kortyzol', 'kortyzol rano', 'kortyzol w surowicy']).c('nmol/l', 0.03625);
    _p('TEST', 'Testosteron', hor, 'ng/ml', null, null).m(2.5, 8.4).f(0.06, 0.82).a(['testosteron', 'testosteron całkowity']).c('nmol/l', 0.2884).c('ng/dl', 0.01);
    _p('FTEST', 'Testosteron wolny', hor, 'pg/ml', null, null).a(['testosteron wolny']);
    _p('E2', 'Estradiol', hor, 'pg/ml', null, null).a(['estradiol', 'e2']).c('pmol/l', 0.2724);
    _p('PRL', 'Prolaktyna', hor, 'ng/ml', null, null).m(4.0, 15.2).f(4.8, 23.3).a(['prolaktyna', 'prl']).c('uiu/ml', 0.0472).c('miu/l', 0.0472);
    _p('FSH', 'FSH', hor, 'mIU/ml', null, null).a(['fsh', 'folitropina']).c('iu/l', 1).c('miu/l', 1);
    _p('LH', 'LH', hor, 'mIU/ml', null, null).a(['lh', 'lutropina']).c('iu/l', 1).c('miu/l', 1);
    _p('PROG', 'Progesteron', hor, 'ng/ml', null, null).a(['progesteron']).c('nmol/l', 0.3145);
    _p('DHEAS', 'DHEA-SO4', hor, 'µg/dl', null, null).a(['dhea so4', 'dhea s', 'dheas', 'siarczan dehydroepiandrosteronu']);
    _p('SHBG', 'SHBG', hor, 'nmol/l', null, null).a(['shbg']);
    _p('AMH', 'AMH', hor, 'ng/ml', null, null).a(['amh', 'hormon antymullerowski']);
    _p('PTH', 'Parathormon (PTH)', hor, 'pg/ml', 15.0, 65.0).a(['parathormon', 'pth', 'parathormon pth']);
    _p('PSA', 'PSA całkowity', hor, 'ng/ml', null, 4.0).a(['psa', 'psa całkowity', 'psa całkowite', 'tpsa', 'antygen swoisty dla stercza']);
    _p('FPSA', 'PSA wolny', hor, 'ng/ml', null, null).a(['psa wolny', 'psa wolne', 'fpsa']);

    // ---------- Żelazo / witaminy ----------
    _p('FE', 'Żelazo', zel, 'µg/dl', 60.0, 170.0).m(65.0, 175.0).f(50.0, 170.0).a(['żelazo', 'fe', 'żelazo w surowicy', 'żelazo fe']).c('umol/l', 5.585);
    _p('FERR', 'Ferrytyna', zel, 'ng/ml', null, null).m(30.0, 400.0).f(15.0, 150.0).a(['ferrytyna', 'ferrytyna w surowicy']).c('ug/l', 1);
    _p('TRF', 'Transferyna', zel, 'mg/dl', 200.0, 360.0).a(['transferyna']).c('g/l', 100);
    _p('TIBC', 'TIBC', zel, 'µg/dl', 250.0, 450.0).a(['tibc', 'całkowita zdolność wiązania żelaza', 'całkowita zdolność wiązania żelaza tibc']).c('umol/l', 5.585);
    _p('UIBC', 'UIBC', zel, 'µg/dl', 110.0, 370.0).a(['uibc', 'utajona zdolność wiązania żelaza']).c('umol/l', 5.585);
    _p('TSAT', 'Wysycenie transferyny', zel, '%', 20.0, 45.0).a(['wysycenie transferyny', 'saturacja transferyny', 'tsat']);
    _p('VITD', 'Witamina D (25-OH)', zel, 'ng/ml', 30.0, 50.0)
        .a([
          'witamina d',
          'witamina d3',
          '25 oh witamina d',
          '25 oh d',
          'witamina d 25 oh',
          'witamina d3 metabolit 25 oh',
          'witamina d metabolit 25 oh',
          'witamina d 25 oh d',
          'witamina d total',
          '25 hydroksywitamina d',
          '25 oh d3',
          'witamina 25 oh d',
          'witamina d3 25 oh',
          'witamina d 25 oh d3'
        ])
        .c('nmol/l', 0.4006);
    _p('B12', 'Witamina B12', zel, 'pg/ml', 197.0, 771.0).a(['witamina b12', 'b12', 'kobalamina', 'wit b12']).c('pmol/l', 1.355);
    _p('FOL', 'Kwas foliowy', zel, 'ng/ml', 3.9, 26.8).a(['kwas foliowy', 'foliany']).c('nmol/l', 0.4413);

    // ---------- Stan zapalny ----------
    _p('OB', 'OB (odczyn Biernackiego)', zap, 'mm/h', 0.0, 15.0)
        .m(0.0, 15.0)
        .f(0.0, 20.0)
        .a(['ob', 'odczyn biernackiego', 'ob odczyn biernackiego', 'esr', 'odczyn biernackiego ob'])
        .c('mm/godz', 1)
        .c('mm/1h', 1)
        .c('mm/godz.', 1)
        .c('mm/1godz', 1);
    _p('CRP', 'CRP', zap, 'mg/l', null, 5.0)
        .a(['crp', 'białko c reaktywne', 'białko crp', 'crp ilościowo', 'crp białko c reaktywne', 'hs crp', 'crp hs', 'białko c reaktywne crp'])
        .c('mg/dl', 10);
    _p('PCTN', 'Prokalcytonina', zap, 'ng/ml', null, 0.5).a(['prokalcytonina']);
    _p('RF', 'Czynnik reumatoidalny (RF)', zap, 'IU/ml', null, 14.0).a(['czynnik reumatoidalny', 'rf', 'czynnik reumatoidalny rf', 'rf ilościowo']);
    _p('ASO', 'ASO', zap, 'IU/ml', null, 200.0).a(['aso', 'antystreptolizyna o']);

    // ---------- Krzepnięcie ----------
    _p('INR', 'INR', krz, '', 0.8, 1.2).a(['inr', 'pt inr', 'czas protrombinowy inr', 'wskaźnik inr']);
    _p('PT', 'Czas protrombinowy (PT)', krz, 's', 9.0, 13.0).a(['czas protrombinowy', 'pt', 'czas protrombinowy pt']).c('sek', 1).c('sek.', 1);
    _p('APTT', 'APTT', krz, 's', 25.0, 37.0).a(['aptt', 'czas kaolinowo kefalinowy', 'czas częściowej tromboplastyny po aktywacji']).c('sek', 1).c('sek.', 1);
    _p('FIB', 'Fibrynogen', krz, 'mg/dl', 200.0, 400.0).a(['fibrynogen']).c('g/l', 100);
    _p('DDIM', 'D-dimery', krz, 'ng/ml', null, 500.0).a(['d dimery', 'd dimer', 'dimery d']).c('ug/l', 1).c('mg/l', 1000).c('ug/ml', 1000);

    // ---------- Immunologia / celiakia / immunoglobuliny ----------
    LabParam ab(LabParam p) => p.c('u/ml', 1).c('ru/ml', 1).c('eu/ml', 1).c('j/ml', 1);
    ab(_p('TTG_IGA', 'Anty-tTG IgA (celiakia)', imm, 'AU/ml', null, 20.0).a([
      'anty ttg iga',
      'anty ttg w klasie iga',
      'ttg iga',
      'przeciwciala przeciw transglutaminazie tkankowej iga',
      'przeciwciala przeciwko transglutaminazie tkankowej w klasie iga',
      'p c p transglutaminazie tkankowej iga',
      'anty transglutaminaza iga',
      'anty tg2 iga'
    ]));
    ab(_p('TTG_IGG', 'Anty-tTG IgG (celiakia)', imm, 'AU/ml', null, 20.0).a([
      'anty ttg igg',
      'anty ttg w klasie igg',
      'ttg igg',
      'przeciwciala przeciw transglutaminazie tkankowej igg',
      'przeciwciala przeciwko transglutaminazie tkankowej w klasie igg',
      'p c p transglutaminazie tkankowej igg',
      'anty transglutaminaza igg',
      'anty tg2 igg'
    ]));
    ab(_p('DGP_IGA', 'Anty-DGP IgA (celiakia)', imm, 'U/ml', null, 20.0).a(['anty dgp iga', 'dgp iga', 'przeciwciala przeciw deamidowanym peptydom gliadyny iga']));
    ab(_p('DGP_IGG', 'Anty-DGP IgG (celiakia)', imm, 'U/ml', null, 20.0).a(['anty dgp igg', 'dgp igg', 'przeciwciala przeciw deamidowanym peptydom gliadyny igg']));
    _p('EMA_IGA', 'Anty-EMA IgA (celiakia)', imm, '', null, null).a(['anty ema iga', 'ema iga', 'przeciwciala przeciw endomysium iga', 'przeciwciala przeciwendomyzjalne iga']);
    _p('IGA', 'IgA całkowite', imm, 'g/l', 0.7, 4.0).a(['iga calkowite', 'immunoglobulina a', 'iga w surowicy', 'iga total']).c('mg/dl', 0.01);
    _p('IGG', 'IgG całkowite', imm, 'g/l', 7.0, 16.0).a(['igg calkowite', 'immunoglobulina g', 'igg w surowicy']).c('mg/dl', 0.01);
    _p('IGM', 'IgM całkowite', imm, 'g/l', 0.4, 2.3).a(['igm calkowite', 'immunoglobulina m', 'igm w surowicy']).c('mg/dl', 0.01);
    _p('IGE', 'IgE całkowite', imm, 'IU/ml', null, 100.0).a(['ige calkowite', 'ige total', 'immunoglobulina e', 'ige w surowicy']).c('kiu/l', 1).c('ku/l', 1);
    ab(_p('CCP', 'Anty-CCP', imm, 'U/ml', null, 17.0).a(['anty ccp', 'przeciwciala przeciw cyklicznemu cytrulinowanemu peptydowi', 'acpa']));

    // ---------- Serce ----------
    _p('NTBNP', 'NT-proBNP', serce, 'pg/ml', null, 125.0).a(['nt pro bnp', 'nt probnp', 'ntprobnp', 'n terminalny propeptyd natriuretyczny typu b']).c('ng/l', 1);
    _p('TROP', 'Troponina', serce, 'ng/l', null, null).a(['troponina', 'troponina t', 'troponina i', 'hs troponina', 'troponina hs']).c('pg/ml', 1);
    _p('HBA1C_IFCC', 'HbA1c (IFCC)', bio, 'mmol/mol', 20.0, 42.0).a(['hemoglobina glikowana ifcc', 'hba1c ifcc']);

    // ---------- Kał ----------
    _p('FOBT', 'Krew utajona w kale', kal, '', null, null).a(['krew utajona w kale', 'krew utajona', 'fobt', 'test na krew utajona']);
    _p('HP_AG', 'Helicobacter pylori – antygen w kale', kal, '', null, null)
        .a(['helicobacter pylori antygen', 'antygen helicobacter pylori', 'helicobacter pylori antygen w kale', 'h pylori antygen']);
    _p('GIARDIA', 'Giardia lamblia w kale', kal, '', null, null).a(['giardia lamblia', 'lamblie', 'giardia lamblia antygen']);
    _p('CALPRO', 'Kalprotektyna w kale', kal, 'µg/g', null, 50.0).a(['kalprotektyna', 'kalprotektyna w kale']).c('mg/kg', 1);
    _p('HP_IGG', 'Helicobacter pylori IgG', imm, '', null, null).a(['helicobacter pylori igg', 'przeciwciala helicobacter pylori igg', 'anty helicobacter pylori igg']);

    // ---------- Mocz – badanie ogólne (tylko w sekcji moczu) ----------
    void u(String key, String name, String unit, double? lo, double? hi, List<String> al, {bool sediment = false}) {
      final x = _p(key, name, moc, unit, lo, hi);
      for (final a in al) {
        (sediment ? sedimentAliases : urineAliases).add(MapEntry(normText(a), x));
      }
    }

    u('U_CLAR', 'Mocz: przejrzystość', '', null, null, ['przejrzystosc', 'klarownosc']);
    u('U_COLOR', 'Mocz: barwa', '', null, null, ['barwa', 'kolor']);
    u('U_SG', 'Mocz: ciężar właściwy', 'g/ml', 1.005, 1.030, ['ciezar wlasciwy', 'gestosc wzgledna', 'ciezar wlasciwy moczu']);
    u('U_PH', 'Mocz: pH', '', 5.0, 7.5, ['ph', 'odczyn', 'odczyn ph']);
    u('U_GLU', 'Mocz: glukoza', 'mg/dl', null, null, ['glukoza', 'cukier']);
    u('U_KET', 'Mocz: ketony', 'mg/dl', null, null, ['ketony', 'ciala ketonowe']);
    u('U_UBG', 'Mocz: urobilinogen', 'mg/dl', 0.0, 1.0, ['urobilinogen']);
    u('U_BIL', 'Mocz: bilirubina', 'mg/dl', null, null, ['bilirubina']);
    u('U_PROT', 'Mocz: białko', 'mg/dl', null, null, ['bialko']);
    u('U_LEU_T', 'Mocz: leukocyty (test paskowy)', '', null, null, ['leukocyty', 'esteraza leukocytarna']);
    u('U_BLOOD', 'Mocz: krew (test paskowy)', '', null, null, ['krew', 'hemoglobina', 'erytrocyty']);
    u('U_NIT', 'Mocz: azotyny', '', null, null, ['azotyny']);
    u('U_ERY_S', 'Osad: erytrocyty', '/µl', null, null, ['erytrocyty', 'erytrocyty swieze', 'erytrocyty wylugowane'], sediment: true);
    u('U_LEU_S', 'Osad: leukocyty', '/µl', null, null, ['leukocyty'], sediment: true);
    u('U_CAST', 'Osad: wałeczki', '/µl', null, null, ['waleczki', 'waleczki szkliste'], sediment: true);
    u('U_BACT', 'Osad: bakterie', '/µl', null, null, ['bakterie', 'bakterie liczne'], sediment: true);
    u('U_NAB', 'Osad: nabłonki płaskie', '/µl', null, null, ['nablonki plaskie', 'komorki nablonka plaskiego'], sediment: true);
    u('U_NAB_O', 'Osad: nabłonki okrągłe', '/µl', null, null, ['nablonki okragle'], sediment: true);
    u('U_YEAST', 'Osad: komórki grzybów', '/µl', null, null, ['komorki grzybow', 'grzyby', 'drozdzaki'], sediment: true);
    u('U_MUC', 'Osad: pasma śluzu', '', null, null, ['pasma sluzu', 'sluz'], sediment: true);
    u('U_CRYST', 'Osad: kryształy', '', null, null, ['krysztaly'], sediment: true);
    _p('UACR', 'Albumina/kreatynina w moczu (ACR)', moc, 'mg/g', null, 30.0).a(['acr', 'wskaznik albumina kreatynina', 'albumina kreatynina w moczu', 'uacr']);

    // ---------- Holter EKG ----------
    _p('HR_MIN', 'Holter: tętno minimalne', ekg, '/min', null, null)
        .a(['minimalna czestosc rytmu', 'czestosc minimalna', 'hr min', 'min hr', 'minimalne tetno', 'tetno minimalne', 'najnizsza czestosc rytmu', 'czestosc rytmu minimalna', 'minimalna czestosc akcji serca'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('HR_AVG', 'Holter: tętno średnie', ekg, '/min', null, null)
        .a(['srednia czestosc rytmu', 'czestosc srednia', 'hr srednie', 'sredni hr', 'srednie tetno', 'tetno srednie', 'srednia czestosc akcji serca', 'czestosc rytmu srednia', 'hr sredni'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('HR_MAX', 'Holter: tętno maksymalne', ekg, '/min', null, null)
        .a(['maksymalna czestosc rytmu', 'czestosc maksymalna', 'hr max', 'max hr', 'maksymalne tetno', 'tetno maksymalne', 'najwyzsza czestosc rytmu', 'czestosc rytmu maksymalna', 'maksymalna czestosc akcji serca'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('SVE', 'Holter: pobudzenia nadkomorowe', ekg, '', null, null)
        .a(['pobudzenia nadkomorowe', 'pobudzen nadkomorowych', 'svpb', 'svpc', 'ekstrasystolie nadkomorowe', 'liczba pobudzen nadkomorowych', 'pobudzenia przedwczesne nadkomorowe', 'sve']);
    _p('VE', 'Holter: pobudzenia komorowe', ekg, '', null, null)
        .a(['pobudzenia komorowe', 'pobudzen komorowych', 'vpb', 'pvc', 'ekstrasystolie komorowe', 'liczba pobudzen komorowych', 'pobudzenia przedwczesne komorowe', 'ves']);
    _p('PAUSE', 'Holter: pauzy > 2 s', ekg, '', null, 0.0).a(['pauzy', 'pauzy powyzej 2 s', 'pauzy 2 s', 'liczba pauz', 'pauzy dluzsze niz 2 s', 'pauzy 2s']);
    _p('PAUSE_MAX', 'Holter: najdłuższa pauza', ekg, 's', null, 2.0).a(['najdluzsza pauza', 'najdluzszy odstep rr', 'max rr', 'najdluzszy rr']).c('ms', 0.001).c('sek', 1);

    _extended();

    for (final x in byKey.values) {
      for (final al in x.aliases) {
        aliases.add(MapEntry(al, x));
      }
    }
    aliases.sort((a, b) => b.key.length.compareTo(a.key.length));
    urineAliases.sort((a, b) => b.key.length.compareTo(a.key.length));
    sedimentAliases.sort((a, b) => b.key.length.compareTo(a.key.length));
  }

  // ======================= Rozszerzona biblioteka =======================
  static void _x(String key, String name, String cat, String unit, double? lo, double? hi, List<String> al, [Map<String, double> conv = const {}]) {
    final p = _p(key, name, cat, unit, lo, hi).a(al);
    conv.forEach((u, f) => p.c(u, f));
  }

  static void _extended() {
    const mgdlMmol = 18.016;
    // ---------- Morfologia – dodatkowe ----------
    _x('RET_ABS', 'Retikulocyty (bezwzględnie)', morf, 'tys/µl', 25, 100, ['retikulocyty bezwzgledne', 'ret abs', 'retikulocyty liczba bezwzgledna'], {'10^9/l': 1, '10^3/ul': 1});
    _x('RETHE', 'RET-He (hemoglobina retikulocytów)', morf, 'pg', 28, 36, ['ret he', 'hemoglobina retikulocytow', 'ret hgb']);
    _x('ESR1H', 'Rozmaz: limfocyty atypowe', morf, '%', null, 0, ['limfocyty atypowe', 'limfocyty odczynowe']);
    _x('BANDS', 'Rozmaz: neutrofile pałeczkowate', morf, '%', 0, 5, ['palki', 'neutrofile paleczkowate', 'granulocyty paleczkowate']);
    _x('SEGS', 'Rozmaz: neutrofile segmentowane', morf, '%', 40, 70, ['segmenty', 'granulocyty segmentowane']);

    // ---------- Biochemia / cukrzyca ----------
    _x('CHE', 'Cholinesteraza', bio, 'U/l', 5300, 12900, ['cholinesteraza', 'cholinoesteraza', 'pseudocholinesteraza', 'che'], {'iu/l': 1, 'kU/l': 1000});
    _x('CERU', 'Ceruloplazmina', bio, 'mg/dl', 20, 60, ['ceruloplazmina'], {'g/l': 100});
    _x('NH3', 'Amoniak', bio, 'µmol/l', 11, 51, ['amoniak', 'amoniak we krwi'], {'ug/dl': 0.587});
    _x('LAC', 'Mleczany', bio, 'mmol/l', 0.5, 2.2, ['mleczany', 'kwas mlekowy', 'laktat', 'mleczan'], {'mg/dl': 0.111});
    _x('OSM', 'Osmolalność surowicy', bio, 'mOsm/kg', 275, 295, ['osmolalnosc', 'osmolalnosc surowicy', 'osmolarnosc']);
    _x('GLOB', 'Globuliny', bio, 'g/dl', 2.0, 3.5, ['globuliny', 'globuliny calkowite'], {'g/l': 0.1});
    _x('PEL_ALB', 'Proteinogram: albuminy', bio, '%', 55.8, 66.1, ['albuminy proteinogram', 'frakcja albumin', 'albuminy w proteinogramie']);
    _x('PEL_A1', 'Proteinogram: alfa-1-globuliny', bio, '%', 2.9, 4.9, ['alfa 1 globuliny', 'alfa1 globuliny', 'globuliny alfa 1']);
    _x('PEL_A2', 'Proteinogram: alfa-2-globuliny', bio, '%', 7.1, 11.8, ['alfa 2 globuliny', 'alfa2 globuliny', 'globuliny alfa 2']);
    _x('PEL_B', 'Proteinogram: beta-globuliny', bio, '%', 8.4, 13.1, ['beta globuliny', 'globuliny beta']);
    _x('PEL_B1', 'Proteinogram: beta-1-globuliny', bio, '%', 4.7, 7.2, ['beta 1 globuliny', 'beta1 globuliny']);
    _x('PEL_B2', 'Proteinogram: beta-2-globuliny', bio, '%', 3.2, 6.5, ['beta 2 globuliny', 'beta2 globuliny']);
    _x('PEL_G', 'Proteinogram: gamma-globuliny', bio, '%', 11.1, 18.8, ['gamma globuliny', 'globuliny gamma']);
    _x('AG_RATIO', 'Stosunek albumin do globulin', bio, '', 1.0, 2.0, ['stosunek albumin globulin', 'wskaznik albuminy globuliny', 'stosunek a g']);
    _x('FRUCT', 'Fruktozamina', bio, 'µmol/l', 205, 285, ['fruktozamina']);
    _x('CPEP', 'Peptyd C', bio, 'ng/ml', 1.1, 4.4, ['peptyd c', 'c peptyd', 'peptyd c na czczo'], {'nmol/l': 3.02, 'pmol/l': 0.00302});
    _x('GLU60', 'Glukoza po 60 min (OGTT)', bio, 'mg/dl', null, 180, ['glukoza po 60 min', 'glukoza 60 min', 'glukoza po 1 godz', 'glukoza po 1 h', 'glukoza 1 h', 'glukoza w 60 minucie', 'ogtt 60 min'], {'mmol/l': mgdlMmol});
    _x('GLU120', 'Glukoza po 120 min (OGTT)', bio, 'mg/dl', null, 140, ['glukoza po 120 min', 'glukoza 120 min', 'glukoza po 2 godz', 'glukoza po 2 h', 'glukoza 2 h', 'glukoza w 120 minucie', 'ogtt 120 min'], {'mmol/l': mgdlMmol});
    _x('INS60', 'Insulina po 60 min (OGTT)', bio, 'µIU/ml', null, null, ['insulina po 60 min', 'insulina 60 min', 'insulina po 1 godz', 'insulina w 60 minucie'], {'mu/l': 1, 'miu/l': 1, 'uu/ml': 1});
    _x('INS120', 'Insulina po 120 min (OGTT)', bio, 'µIU/ml', null, null, ['insulina po 120 min', 'insulina 120 min', 'insulina po 2 godz', 'insulina w 120 minucie'], {'mu/l': 1, 'miu/l': 1, 'uu/ml': 1});
    _x('BHB', 'Beta-hydroksymaślan', bio, 'mmol/l', null, 0.3, ['beta hydroksymaslan', 'kwas beta hydroksymaslowy', 'ketony we krwi']);
    _x('ACE', 'Konwertaza angiotensyny (ACE)', bio, 'U/l', 8, 52, ['konwertaza angiotensyny', 'ace', 'enzym konwertujacy angiotensyne']);

    // ---------- Lipidy ----------
    _x('APOA1', 'Apolipoproteina A1', lip, 'mg/dl', 110, 205, ['apolipoproteina a1', 'apolipoproteina a 1', 'apo a1', 'apoa1', 'apo a 1'], {'g/l': 100});
    _x('APOB', 'Apolipoproteina B', lip, 'mg/dl', null, 100, ['apolipoproteina b', 'apo b', 'apob', 'apolipoproteina b100'], {'g/l': 100});
    _x('SDLDL', 'Małe gęste LDL (sdLDL)', lip, 'mg/dl', null, 35, ['sdldl', 'male geste ldl', 'sd ldl'], {'mmol/l': 38.67});
    _x('LDL_D', 'Cholesterol LDL bezpośredni', lip, 'mg/dl', null, 115, ['ldl bezposredni', 'cholesterol ldl bezposredni', 'ldl oznaczany bezposrednio'], {'mmol/l': 38.67});

    // ---------- Wątroba / trzustka ----------
    _x('BILI', 'Bilirubina pośrednia', wat, 'mg/dl', 0.2, 0.8, ['bilirubina posrednia', 'bilirubina wolna', 'bilirubina niesprzezona'], {'umol/l': 0.0585});
    _x('GLDH', 'GLDH', wat, 'U/l', null, 7, ['gldh', 'dehydrogenaza glutaminianowa']);
    _x('ELAST_K', 'Elastaza trzustkowa w kale', kal, 'µg/g', 200, null, ['elastaza trzustkowa', 'elastaza 1', 'elastaza w kale', 'elastaza trzustkowa w kale']);
    _x('AMY_U', 'Amylaza w moczu', moc, 'U/l', null, 460, ['amylaza w moczu', 'diastaza', 'diastaza w moczu']);

    // ---------- Nerki / elektrolity / mocz dobowy ----------
    _x('CYSC', 'Cystatyna C', ner, 'mg/l', 0.6, 1.0, ['cystatyna c', 'cystatyna']);
    _x('EGFR_CYS', 'eGFR (cystatyna C)', ner, 'ml/min/1,73m²', 90, null, ['egfr cystatyna', 'egfr wg cystatyny c', 'egfr cystatyna c', 'egfr ckd epi cystatyna']);
    _x('B2M', 'Beta-2-mikroglobulina', ner, 'mg/l', 0.8, 2.2, ['beta 2 mikroglobulina', 'b2 mikroglobulina', 'beta2 mikroglobulina', 'b 2 mikroglobulina']);
    _x('CAJ', 'Wapń zjonizowany', ner, 'mmol/l', 1.15, 1.35, ['wapn zjonizowany', 'ca zjonizowany', 'ca2', 'wapn zjonizowany ca2']);
    _x('U24_PROT', 'Białko w dobowej zbiórce moczu', moc, 'g/24h', null, 0.15, ['bialkomocz dobowy', 'bialko w dobowej zbiorce moczu', 'dobowa utrata bialka', 'bialko w moczu dobowym', 'bialko calkowite w dobowej zbiorce moczu'], {'mg/24h': 0.001});
    _x('U_ALB', 'Albumina w moczu', moc, 'mg/l', null, 20, ['albumina w moczu', 'mikroalbuminuria', 'mikroalbumina w moczu']);
    _x('U_CREA', 'Kreatynina w moczu', moc, 'mg/dl', null, null, ['kreatynina w moczu', 'kreatynina w moczu jednorazowym'], {'mmol/l': 11.31, 'umol/l': 0.01131});
    _x('CRCL', 'Klirens kreatyniny', ner, 'ml/min', 90, 140, ['klirens kreatyniny', 'klirens kreatyniny endogennej']);
    _x('U_NA', 'Sód w moczu', moc, 'mmol/l', null, null, ['sod w moczu', 'sod w dobowej zbiorce moczu']);
    _x('U_K', 'Potas w moczu', moc, 'mmol/l', null, null, ['potas w moczu', 'potas w dobowej zbiorce moczu']);
    _x('U_CA', 'Wapń w moczu', moc, 'mg/24h', null, 300, ['wapn w moczu', 'wapn w dobowej zbiorce moczu', 'kalciuria']);
    _x('U_UA', 'Kwas moczowy w moczu', moc, 'mg/24h', null, 800, ['kwas moczowy w moczu', 'kwas moczowy w dobowej zbiorce moczu']);
    _x('U_VOL', 'Objętość dobowej zbiórki moczu', moc, 'ml', 800, 2500, ['objetosc moczu', 'diureza', 'objetosc zbiorki', 'diureza dobowa']);

    // ---------- Tarczyca ----------
    _x('THYRO', 'Tyreoglobulina', tar, 'ng/ml', 3.5, 77, ['tyreoglobulina', 'tyreoglobulina tg']);
    _x('CALCIT', 'Kalcytonina', tar, 'pg/ml', null, 10, ['kalcytonina']);
    _x('TT4', 'Tyroksyna całkowita (T4)', tar, 'µg/dl', 5.1, 14.1, ['tyroksyna calkowita', 'tt4', 't4 calkowita', 't4'], {'nmol/l': 0.0777});
    _x('TT3', 'Trójjodotyronina całkowita (T3)', tar, 'ng/dl', 80, 200, ['trojjodotyronina calkowita', 'tt3', 't3 calkowita', 't3'], {'nmol/l': 65.1});
    _x('RT3', 'Odwrotna T3 (rT3)', tar, 'ng/dl', 10, 24, ['rt3', 'odwrotna t3', 'reverse t3']);

    // ---------- Hormony ----------
    _x('ACTH', 'ACTH', hor, 'pg/ml', 7.2, 63.3, ['acth', 'kortykotropina', 'hormon adrenokortykotropowy']);
    _x('GH', 'Hormon wzrostu (GH)', hor, 'ng/ml', null, null, ['hormon wzrostu', 'gh', 'somatotropina', 'hgh']);
    _x('IGF1', 'IGF-1', hor, 'ng/ml', null, null, ['igf 1', 'igf1', 'somatomedyna c', 'insulinopodobny czynnik wzrostu 1']);
    _x('ALDO', 'Aldosteron', hor, 'pg/ml', null, null, ['aldosteron'], {'ng/dl': 10, 'pmol/l': 0.3605});
    _x('RENIN', 'Renina', hor, 'µIU/ml', null, null, ['renina', 'renina bezposrednia', 'aktywnosc reninowa osocza']);
    _x('ANDRO', 'Androstendion', hor, 'ng/ml', null, null, ['androstendion', 'androstenedion'], {'nmol/l': 0.2865});
    _x('OHP17', '17-OH-progesteron', hor, 'ng/ml', null, null, ['17 oh progesteron', '17 hydroksyprogesteron', '17 ohp', '17 oh p'], {'nmol/l': 0.3305});
    _x('DHT', 'Dihydrotestosteron', hor, 'pg/ml', null, null, ['dihydrotestosteron', 'dht']);
    _x('HCG', 'Beta-hCG', hor, 'mIU/ml', null, 5, ['beta hcg', 'b hcg', 'hcg', 'gonadotropina kosmowkowa', 'beta hcg ilosciowo', 'hcg calkowite'], {'iu/l': 1, 'miu/ml': 1});
    _x('VITD125', 'Witamina D 1,25(OH)₂', zel, 'pg/ml', 19.9, 79.3, ['1 25 oh 2 d', '1 25 dihydroksywitamina d', 'witamina d 1 25 oh 2', '1 25 oh 2 witamina d', 'kalcytriol']);
    _x('ESTRON', 'Estron', hor, 'pg/ml', null, null, ['estron']);
    _x('MPRL', 'Makroprolaktyna', hor, '%', null, null, ['makroprolaktyna', 'prolaktyna po peg']);
    _x('INHB', 'Inhibina B', hor, 'pg/ml', null, null, ['inhibina b']);
    _x('METAN', 'Metoksykatecholaminy', hor, 'µg/24h', null, null, ['metoksykatecholaminy', 'metanefryny', 'normetanefryny']);
    _x('CORT_U', 'Kortyzol w dobowej zbiórce moczu', hor, 'µg/24h', null, null, ['kortyzol w moczu', 'wolny kortyzol w moczu', 'kortyzol w dobowej zbiorce moczu']);
    _x('CORT_S', 'Kortyzol w ślinie', hor, 'nmol/l', null, null, ['kortyzol w slinie', 'kortyzol slina']);

    // ---------- Witaminy i mikroelementy ----------
    _x('VITA', 'Witamina A', zel, 'mg/l', 0.3, 0.8, ['witamina a', 'retinol'], {'ug/dl': 0.01, 'umol/l': 0.2865});
    _x('VITE', 'Witamina E', zel, 'mg/l', 5, 18, ['witamina e', 'alfa tokoferol', 'tokoferol'], {'umol/l': 0.4307});
    _x('VITB1', 'Witamina B1', zel, 'µg/l', 28, 85, ['witamina b1', 'tiamina']);
    _x('VITB6', 'Witamina B6', zel, 'µg/l', 5, 50, ['witamina b6', 'pirydoksyna', 'fosforan pirydoksalu']);
    _x('VITC', 'Witamina C', zel, 'mg/dl', 0.4, 2.0, ['witamina c', 'kwas askorbinowy']);
    _x('VITK', 'Witamina K', zel, 'ng/ml', 0.1, 2.2, ['witamina k', 'witamina k1', 'filochinon']);
    _x('ZN', 'Cynk', zel, 'µg/dl', 70, 120, ['cynk', 'cynk w surowicy'], {'umol/l': 6.54});
    _x('CU', 'Miedź', zel, 'µg/dl', 70, 140, ['miedz', 'miedz w surowicy'], {'umol/l': 6.355});
    _x('SE', 'Selen', zel, 'µg/l', 70, 150, ['selen', 'selen w surowicy']);
    _x('STFR', 'Rozpuszczalny receptor transferyny', zel, 'mg/l', 0.76, 1.76, ['rozpuszczalny receptor transferyny', 'stfr']);
    _x('HOLOTC', 'Holotranskobalamina (aktywna B12)', zel, 'pmol/l', 35, null, ['holotranskobalamina', 'aktywna witamina b12', 'holo tc', 'holotc']);
    _x('MMA', 'Kwas metylomalonowy', zel, 'µmol/l', null, 0.4, ['kwas metylomalonowy', 'mma']);
    _x('OMEGA3', 'Indeks omega-3', zel, '%', 8, null, ['indeks omega 3', 'omega 3 index']);

    // ---------- Stan zapalny ----------
    _x('IL6', 'Interleukina 6', zap, 'pg/ml', null, 7, ['interleukina 6', 'il 6', 'il6']);
    _x('SAA', 'Białko amyloidu A (SAA)', zap, 'mg/l', null, 6.4, ['saa', 'bialko amyloidu a', 'amyloid a']);

    // ---------- Krzepnięcie ----------
    _x('TT', 'Czas trombinowy (TT)', krz, 's', 14, 21, ['czas trombinowy', 'tt', 'czas trombinowy tt']);
    _x('PTI', 'Wskaźnik protrombinowy', krz, '%', 70, 130, ['wskaznik protrombinowy', 'wskaznik quicka', 'wskaznik pt']);
    _x('AT3', 'Antytrombina III', krz, '%', 80, 120, ['antytrombina iii', 'antytrombina', 'at iii', 'at3']);
    _x('PROTC', 'Białko C (aktywność)', krz, '%', 70, 140, ['bialko c aktywnosc', 'bialko c', 'aktywnosc bialka c']);
    _x('PROTS', 'Białko S (wolne)', krz, '%', 60, 140, ['bialko s', 'wolne bialko s', 'bialko s wolne']);
    _x('F8', 'Czynnik VIII', krz, '%', 50, 150, ['czynnik viii', 'aktywnosc czynnika viii']);
    _x('LA', 'Antykoagulant tocznia', krz, '', null, null, ['antykoagulant tocznia', 'antykoagulant toczniowy', 'la']);

    // ---------- Immunologia ----------
    _x('ANA', 'Przeciwciała przeciwjądrowe (ANA)', imm, '', null, null, ['ana', 'przeciwciala przeciwjadrowe', 'ana screen', 'ana1', 'ana hep 2', 'przeciwciala przeciwjadrowe ana']);
    _x('ANCA', 'ANCA', imm, '', null, null, ['anca', 'p anca', 'c anca', 'przeciwciala anca']);
    _x('DSDNA', 'Anty-dsDNA', imm, 'IU/ml', null, 10, ['anty dsdna', 'przeciwciala przeciw dsdna', 'ds dna']);
    _x('C3', 'Dopełniacz C3', imm, 'g/l', 0.9, 1.8, ['c3', 'dopelniacz c3', 'skladowa c3', 'c3c'], {'mg/dl': 0.01});
    _x('C4', 'Dopełniacz C4', imm, 'g/l', 0.1, 0.4, ['c4', 'dopelniacz c4', 'skladowa c4'], {'mg/dl': 0.01});
    _x('TRYPT', 'Tryptaza', imm, 'µg/l', null, 11.4, ['tryptaza']);
    _x('ECP', 'Eozynofilowe białko kationowe (ECP)', imm, 'µg/l', null, 24, ['ecp', 'eozynofilowe bialko kationowe']);
    _x('ASCA', 'ASCA', imm, '', null, null, ['asca', 'przeciwciala asca']);
    _x('AGA_IGA', 'Przeciwciała antygliadynowe IgA', imm, 'U/ml', null, null, ['aga iga', 'przeciwciala antygliadynowe iga', 'anty gliadyna iga']);
    _x('AGA_IGG', 'Przeciwciała antygliadynowe IgG', imm, 'U/ml', null, null, ['aga igg', 'przeciwciala antygliadynowe igg', 'anty gliadyna igg']);

    // ---------- Infekcje ----------
    _x('HBSAG', 'HBsAg (WZW B)', inf, '', null, null, ['hbsag', 'antygen hbs', 'hbs ag', 'hbs antygen']);
    _x('AHBS', 'Anty-HBs (odporność WZW B)', inf, 'mIU/ml', 10, null, ['anty hbs', 'przeciwciala anty hbs', 'anty hbs ilosciowo'], {'iu/l': 1});
    _x('AHBC', 'Anty-HBc total', inf, '', null, null, ['anty hbc', 'anty hbc total', 'anty hbc calkowite']);
    _x('HCV', 'Anty-HCV (WZW C)', inf, '', null, null, ['anty hcv', 'przeciwciala anty hcv', 'hcv ab']);
    _x('HAV', 'Anty-HAV IgG (WZW A)', inf, '', null, null, ['anty hav igg', 'anty hav total', 'anty hav']);
    _x('HIV', 'HIV Ag/Ab', inf, '', null, null, ['hiv ag ab', 'hiv combo', 'hiv 1 2', 'hiv 1 2 ag ab', 'hiv', 'antygen p24 i przeciwciala anty hiv']);
    _x('VDRL', 'Kiła (VDRL/RPR)', inf, '', null, null, ['vdrl', 'kila vdrl', 'rpr', 'odczyn vdrl', 'usr']);
    _x('TPHA', 'Kiła (TPHA)', inf, '', null, null, ['tpha', 'treponema pallidum', 'kila tpha']);
    _x('TOXO_G', 'Toksoplazmoza IgG', inf, 'IU/ml', null, null, ['toksoplazmoza igg', 'toxoplasma gondii igg', 'toxoplasma igg', 'toxo igg']);
    _x('TOXO_M', 'Toksoplazmoza IgM', inf, '', null, null, ['toksoplazmoza igm', 'toxoplasma gondii igm', 'toxoplasma igm', 'toxo igm']);
    _x('CMV_G', 'CMV IgG', inf, 'U/ml', null, null, ['cmv igg', 'cytomegalia igg', 'cytomegalovirus igg']);
    _x('CMV_M', 'CMV IgM', inf, '', null, null, ['cmv igm', 'cytomegalia igm', 'cytomegalovirus igm']);
    _x('EBV_VCAM', 'EBV VCA IgM', inf, '', null, null, ['ebv vca igm', 'ebv igm']);
    _x('EBV_VCAG', 'EBV VCA IgG', inf, '', null, null, ['ebv vca igg', 'ebv igg']);
    _x('EBV_EBNA', 'EBV EBNA IgG', inf, '', null, null, ['ebv ebna igg', 'ebna igg', 'ebna 1 igg']);
    _x('BORR_G', 'Borelioza IgG', inf, '', null, null, ['borelioza igg', 'borrelia igg', 'borrelia burgdorferi igg', 'borelioza igg elisa']);
    _x('BORR_M', 'Borelioza IgM', inf, '', null, null, ['borelioza igm', 'borrelia igm', 'borrelia burgdorferi igm', 'borelioza igm elisa']);
    _x('RUB_G', 'Różyczka IgG', inf, 'IU/ml', 10, null, ['rozyczka igg', 'rubella igg', 'wirus rozyczki igg']);
    _x('RUB_M', 'Różyczka IgM', inf, '', null, null, ['rozyczka igm', 'rubella igm']);
    _x('VZV_G', 'Ospa wietrzna (VZV) IgG', inf, '', null, null, ['vzv igg', 'ospa wietrzna igg', 'varicella zoster igg']);
    _x('COVID', 'SARS-CoV-2', inf, '', null, null, ['sars cov 2', 'covid 19', 'sars cov 2 antygen', 'sars cov 2 rt pcr', 'koronawirus sars cov 2']);
    _x('COVID_IGG', 'SARS-CoV-2 IgG', inf, '', null, null, ['sars cov 2 igg', 'przeciwciala sars cov 2 igg', 'covid 19 igg']);
    _x('FLU', 'Grypa A/B (antygen)', inf, '', null, null, ['grypa a b', 'grypa antygen', 'influenza a b', 'wirus grypy']);
    _x('STREP', 'Paciorkowiec (strep test)', inf, '', null, null, ['strep a', 'paciorkowce grupy a', 'streptococcus pyogenes', 'szybki test paciorkowcowy']);
    _x('CHLAM', 'Chlamydia trachomatis', inf, '', null, null, ['chlamydia trachomatis', 'chlamydia']);
    _x('MYCO_M', 'Mycoplasma pneumoniae IgM', inf, '', null, null, ['mycoplasma pneumoniae igm', 'mykoplazma igm']);
    _x('QUANT', 'Test IGRA (gruźlica)', inf, '', null, null, ['quantiferon', 'quantiferon tb', 'igra', 'test igra']);

    // ---------- Kał ----------
    _x('PARAS', 'Pasożyty w kale', kal, '', null, null, ['jaja pasozytow', 'pasozyty jelitowe', 'badanie kalu na pasozyty', 'pasozyty', 'jaja i cysty pasozytow']);
    _x('CDIFF', 'Clostridioides difficile', kal, '', null, null, ['clostridioides difficile', 'clostridium difficile', 'toksyna a b clostridium', 'c difficile toksyna', 'gdh clostridium']);
    _x('ROTA', 'Rotawirusy w kale', kal, '', null, null, ['rotawirusy', 'rotawirus', 'rotawirusy antygen']);
    _x('ADENO', 'Adenowirusy w kale', kal, '', null, null, ['adenowirusy', 'adenowirus']);
    _x('NORO', 'Norowirusy w kale', kal, '', null, null, ['norowirusy', 'norowirus']);
    _x('LACTOF', 'Laktoferyna w kale', kal, '', null, null, ['laktoferyna', 'laktoferyna w kale']);
    _x('FIT', 'Krew utajona w kale (ilościowo, FIT)', kal, 'µg/g', null, 20, ['fit', 'krew utajona ilosciowo', 'hemoglobina w kale', 'test immunochemiczny fit']);

    // ---------- Serce ----------
    _x('CKMB', 'CK-MB', serce, 'U/l', null, 25, ['ck mb', 'kinaza kreatynowa mb', 'izoenzym ck mb'], {'iu/l': 1});
    _x('CKMB_M', 'CK-MB masa', serce, 'ng/ml', null, 5, ['ck mb masa', 'ck mb mass']);
    _x('MYO', 'Mioglobina', serce, 'ng/ml', 25, 72, ['mioglobina']);
    _x('BNP', 'BNP', serce, 'pg/ml', null, 100, ['bnp', 'peptyd natriuretyczny typu b']);

    // ---------- Markery nowotworowe ----------
    _x('CEA', 'CEA', onko, 'ng/ml', null, 5, ['cea', 'antygen karcynoembrionalny']);
    _x('AFP', 'AFP', onko, 'ng/ml', null, 7, ['afp', 'alfa fetoproteina', 'alfa 1 fetoproteina'], {'iu/ml': 1.21});
    _x('CA125', 'CA 125', onko, 'U/ml', null, 35, ['ca 125', 'ca125', 'ca 125 ii']);
    _x('CA199', 'CA 19-9', onko, 'U/ml', null, 37, ['ca 19 9', 'ca19 9', 'ca 199']);
    _x('CA153', 'CA 15-3', onko, 'U/ml', null, 25, ['ca 15 3', 'ca15 3', 'ca 153']);
    _x('CA724', 'CA 72-4', onko, 'U/ml', null, 6.9, ['ca 72 4', 'ca72 4']);
    _x('HE4', 'HE4', onko, 'pmol/l', null, 140, ['he4', 'he 4']);
    _x('ROMA', 'Algorytm ROMA', onko, '%', null, null, ['roma', 'algorytm roma', 'wskaznik roma']);
    _x('NSE', 'NSE', onko, 'ng/ml', null, 16.3, ['nse', 'enolaza neuronowo swoista']);
    _x('SCC', 'SCC', onko, 'ng/ml', null, 1.5, ['scc', 'scc ag', 'antygen raka plaskonablonkowego']);
    _x('CYFRA', 'CYFRA 21-1', onko, 'ng/ml', null, 3.3, ['cyfra 21 1', 'cyfra']);
    _x('CGA', 'Chromogranina A', onko, 'ng/ml', null, 100, ['chromogranina a', 'chromogranina']);
    _x('PSA_RATIO', 'Stosunek PSA wolny/całkowity', onko, '%', 25, null, ['wskaznik fpsa tpsa', 'stosunek psa wolny calkowity', 'fpsa tpsa', 'stosunek fpsa tpsa', 'psa wolny psa calkowity']);
    _x('S100', 'Białko S100', onko, 'µg/l', null, 0.105, ['bialko s100', 's100']);
    _x('PROGRP', 'ProGRP', onko, 'pg/ml', null, 63, ['progrp', 'pro grp']);

    // ---------- Gazometria ----------
    _x('BG_PH', 'Gazometria: pH', gaz, '', 7.35, 7.45, ['ph krwi', 'ph gazometria', 'ph', 'ph krwi tetniczej', 'ph krwi zylnej', 'ph krwi wlosniczkowej']);
    _x('PCO2', 'Gazometria: pCO₂', gaz, 'mmHg', 35, 45, ['pco2', 'pco 2', 'cisnienie parcjalne co2', 'pco2 t'], {'kpa': 7.50});
    _x('PO2', 'Gazometria: pO₂', gaz, 'mmHg', 75, 100, ['po2', 'po 2', 'cisnienie parcjalne o2', 'po2 t'], {'kpa': 7.50});
    _x('HCO3', 'Gazometria: HCO₃⁻', gaz, 'mmol/l', 22, 26, ['hco3', 'hco3 akt', 'hco3 std', 'wodoroweglany', 'hco3 aktualne', 'hco3 standardowe', 'sbc']);
    _x('BE', 'Gazometria: nadmiar zasad (BE)', gaz, 'mmol/l', -2.5, 2.5, ['be', 'nadmiar zasad', 'be ecf', 'be b', 'abe', 'sbe', 'be ecf c']);
    _x('SO2', 'Gazometria: saturacja O₂', gaz, '%', 95, 99, ['so2', 'sat o2', 'sao2', 'so2 c', 'wysycenie tlenem']);
    _x('TCO2', 'Gazometria: ctCO₂', gaz, 'mmol/l', 23, 29, ['tco2', 'ctco2', 'calkowity co2']);

    // ---------- Leki (stężenia) ----------
    _x('DIGOX', 'Digoksyna', leki, 'ng/ml', 0.8, 2.0, ['digoksyna']);
    _x('LITH', 'Lit', leki, 'mmol/l', 0.6, 1.2, ['lit', 'lit w surowicy']);
    _x('VALP', 'Kwas walproinowy', leki, 'µg/ml', 50, 100, ['kwas walproinowy', 'walproiniany', 'walproinian']);
    _x('CARB', 'Karbamazepina', leki, 'µg/ml', 4, 12, ['karbamazepina']);
    _x('VANCO', 'Wankomycyna', leki, 'µg/ml', 10, 20, ['wankomycyna']);
    _x('TACRO', 'Takrolimus', leki, 'ng/ml', 5, 15, ['takrolimus', 'tacrolimus']);
    _x('PHENY', 'Fenytoina', leki, 'µg/ml', 10, 20, ['fenytoina']);

    // ---------- Wzrok (badanie okulistyczne) – także z parsera badań wzroku ----------
    for (final side in const [('R', 'OP (prawe)'), ('L', 'OL (lewe)')]) {
      final s = side.$1, nm = side.$2;
      _p('EYE_VA_$s', 'Ostrość wzroku bez korekcji $nm', eye, '', 0.8, null);
      _p('EYE_VACC_$s', 'Ostrość wzroku z korekcją $nm', eye, '', 0.8, null);
      _p('EYE_VAN_$s', 'Ostrość wzroku do bliży $nm', eye, '', null, null);
      _p('EYE_SPH_$s', 'Sfera (SPH) $nm', eye, 'dpt', null, null);
      _p('EYE_CYL_$s', 'Cylinder (CYL) $nm', eye, 'dpt', null, null);
      _p('EYE_AX_$s', 'Oś cylindra $nm', eye, '°', null, null);
      _p('EYE_ADD_$s', 'Addycja (ADD) $nm', eye, 'dpt', null, null);
      _p('EYE_SE_$s', 'Ekwiwalent sferyczny $nm', eye, 'dpt', null, null);
      _p('EYE_IOP_$s', 'Ciśnienie wewnątrzgałkowe $nm', eye, 'mmHg', 10, 21);
      _p('EYE_AL_$s', 'Długość osiowa gałki $nm', eye, 'mm', null, null);
      _p('EYE_CCT_$s', 'Grubość rogówki (pachymetria) $nm', eye, 'µm', null, null);
      _p('EYE_K1_$s', 'Keratometria K1 $nm', eye, 'D', null, null);
      _p('EYE_K2_$s', 'Keratometria K2 $nm', eye, 'D', null, null);
      _p('EYE_RNFL_$s', 'OCT: średnia grubość RNFL $nm', eye, 'µm', 80, null);
      _p('EYE_CMT_$s', 'OCT: grubość centralna siatkówki $nm', eye, 'µm', null, null);
      _p('EYE_MD_$s', 'Pole widzenia MD $nm', eye, 'dB', -2.0, null);
      _p('EYE_CD_$s', 'Stosunek C/D tarczy nerwu $nm', eye, '', null, 0.6);
    }
    _p('EYE_PD', 'Rozstaw źrenic (PD)', eye, 'mm', null, null).a(['rozstaw zrenic', 'pd', 'odleglosc miedzyzreniczna']);
  }
}
